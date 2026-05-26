# Phase 14b — WASM Bundle Performance: Caching, Trimming, Progress UI

**Goal:** Make the 20.6 MB gzipped WASM bundle stop being a deal-breaker. Three sub-tracks, shipped in order:

- **B2 (Service-worker caching) — ship first.** Repeat visits transfer ~0 bytes. First visit unchanged.
- **B1 (WASM trimming) — ship second.** First-visit bundle drops from ~20 MB gzipped to ~14 MB. Doesn't help repeat visits (already cached).
- **B4 (Progress UI) — ship third.** First-visit users see a real percent during the download instead of a blank screen.

**Scope:** Driver-side and build-pipeline only. No Swift API surface changes. The `Swiflow.render(into:)` story stays exactly as it is today.

**Non-goals (explicitly punted):**
- SSG / pre-rendering Swift to HTML at build time. Post-1.0.
- Multi-WASM module splitting. Blocked on SwiftWasm toolchain maturity.
- Runtime replacement (skip Foundation, write a thin JS bridge). Multi-quarter project, post-1.0.
- `--disable-reflection-metadata`. Blocked on `@State`'s `Mirror` dependency — see "The reflection wall" below.

---

## Honest framing

The 20.6 MB gzipped is mostly the Swift runtime + Foundation + JavaScriptKit. A `Counter` component costs ~1 KB on top. So "lazy loading components" doesn't help; the runtime is what we ship, components are noise.

This phase doesn't fix that. It mitigates it on two axes:

1. **Repeat-visit cost** — service worker turns 20.6 MB into 0 bytes after visit #1. This is the single biggest user-perceived UX lever available pre-1.0.
2. **First-visit cost** — trimming the WASM with `-Osize` + `wasm-opt -Oz` should drop it 25-30% to ~14 MB. Not transformative, but the difference between "30s on 4G" and "20s on 4G."

Combined honest positioning after Phase 14b ships: **Swiflow is for apps users invest in.** First visit costs 14 MB and ~20s on 4G; visit #2 onward is free. That's viable for dashboards, internal tools, SaaS products, editors. It's not viable for one-off marketing pages — that's SSG-territory and we're not walking through that door pre-1.0.

---

## Track 1 — Service worker caching (B2)

### What ships

- New file `js-driver/swiflow-sw.js` (~150 lines, vanilla JS).
- `swiflow build` emits `swiflow-manifest.json` next to the WASM with the SHA256 of each artifact in the bundle (App.wasm, index.js, runtime.js, instantiate.js, platforms/browser.js).
- The existing driver (`swiflow-driver.js`) registers the service worker on script load — unless `window.SWIFLOW_DEV` is set.
- Service worker is also embedded into the CLI binary the same way the driver is today (via `Scripts/embed-driver.swift` + `Sources/SwiflowCLI/EmbeddedDriver.swift`), so `swiflow init` ships a working caching template.

### How caching works

The service worker uses **two caches, keyed by content hash:**

- `swiflow-runtime-v<sha256-of-manifest>` — the JS runtime files. Small (~12 KB gzipped).
- `swiflow-wasm-v<sha256-of-app-wasm>` — the WASM. Big (~14 MB gzipped after trim).

Splitting them means a Swift-source edit (which changes App.wasm) doesn't invalidate the JS runtime cache, and vice versa. Each artifact's cache lives until its bytes change.

**Install:** read `swiflow-manifest.json`, pre-cache the two namespaces from the listed URLs. The user's first visit completes the install in the background while the page is already running off the network response — install does not block first paint.

**Fetch:** for any request whose URL appears in the manifest, serve from cache. For everything else, defer to the network (pass-through).

**Activate:** delete any `swiflow-*` caches whose hash isn't current.

### Manifest shape

`swiflow-manifest.json` lives at the same URL prefix as the WASM, content-served verbatim:

```json
{
  "version": "1",
  "wasm": {
    "url": ".build/plugins/PackageToJS/outputs/Package/App.wasm",
    "sha256": "ea7a…"
  },
  "runtime": [
    { "url": ".../index.js",       "sha256": "..." },
    { "url": ".../instantiate.js", "sha256": "..." },
    { "url": ".../runtime.js",     "sha256": "..." },
    { "url": ".../platforms/browser.js", "sha256": "..." }
  ]
}
```

Manifest is small (a few hundred bytes); it can be re-fetched on every visit without measurable cost. The hashes inside drive cache key invalidation.

### Build-pipeline change

`swiflow build` (Sources/SwiflowCLI/Commands/BuildCommand.swift) gets a new step after the PackageToJS invocation: walk the output directory, SHA256 each named artifact, write the manifest.

That's the only build-side change. The WASM filenames stay as PackageToJS emits them; the manifest is the layer that knows the current hashes.

### Dev override

`swiflow dev` already injects `window.SWIFLOW_DEV = true` into the page (Phase 8 wired this up for HMR). The driver checks the flag before registering a service worker — and on dev page-load, if any `swiflow-*` service worker is registered from a previous release-mode visit, **unregister it and reload once** to guarantee HMR doesn't fight a stale cache. Loud console message documents the auto-unregistration.

### Out of scope for this track

- Cross-origin / CDN-hosted WASM. Service workers are same-origin. If a user deploys the WASM to a CDN at a different origin, this caching layer doesn't intercept. We'll document the constraint; we won't solve it. (Most early Swiflow deploys will be single-origin static hosts anyway.)
- Stale-while-revalidate / background updates. Hash change = new bytes = full re-download. Simpler, predictable.
- Cache eviction beyond "delete old hashes." Browsers manage their own quotas; we trust that.

---

## Track 2 — WASM trimming (B1)

### Step 1: Audit (deliverable in itself)

Before changing anything, produce `docs/perf/2026-05-26-wasm-bundle-audit.md` documenting where the current 20.6 MB lives. Tools, all actively maintained:

| Tool | Source | Use |
|---|---|---|
| `wasm-objdump -h App.wasm` | [wabt](https://github.com/WebAssembly/wabt) | Section sizes |
| `wasm-opt --func-metrics App.wasm` | [Binaryen](https://github.com/WebAssembly/binaryen) | Per-function bytes, sorted descending |
| `wasm-tools dump App.wasm` | [Bytecode Alliance](https://github.com/bytecodealliance/wasm-tools) | Lower-level section inspection |
| `wasm-decompile App.wasm` | wabt | Spot-check what big functions do |

The audit captures:

- Section sizes (code, data, types, names, etc.)
- Top 30 functions by bytes (with demangled Swift names where possible)
- Best guess at attribution: Swift stdlib / Foundation / JavaScriptKit / Swiflow / app code

The audit is the baseline. Future trimming work — whether in this phase or post-1.0 — should refer back to it to know what moved.

### Step 2: Compiler-side trimming

Two changes in `Sources/SwiflowCLI/Commands/BuildCommand.swift` → `BuildInvocation`:

```swift
// Currently passed:
"--Xswiftc", "-O"

// Replace with:
"--Xswiftc", "-Osize"
```

Expected saving: 10-20% of the WASM code section. Imperceptible perf cost for the workloads Swiflow targets (DOM diff, not numerical compute).

Also worth measuring (separate decision per result):
- `--Xswiftc -wmo` — whole-module optimization. May already be default in release; check.
- `--Xswiftc -gnone` for release-only — strip debug info. We want DWARF in dev; release shouldn't carry it.

### Step 3: Post-process with wasm-opt

After PackageToJS produces `App.wasm`, run:

```
wasm-opt -Oz --strip-debug --strip-producers App.wasm -o App.wasm
```

Expected saving: 5-15% additional on top of `-Osize`.

**Dependency strategy** — we have three options and need to pick one:

| Option | Pros | Cons |
|---|---|---|
| Require system `wasm-opt` (e.g., `brew install binaryen`) | Smallest CLI binary | Footgun for new users |
| Vendor a `wasm-opt` binary per platform inside the CLI | Just works | Bloats the CLI release artifacts; license + signing concerns |
| Skip if not present, warn loudly | Easy to ship | Most users will skip and not know they should run it |

**Recommendation:** require system `wasm-opt`. Document it in the prereqs alongside Swift SDK 6.3. Add a `swiflow doctor` subcommand (a small new addition this phase) that verifies presence of `swift`, the WASM SDK, and `wasm-opt`, and prints `brew install binaryen` or equivalent if missing. Honest, no auto-magic, no binary distribution.

### Step 4: Name section strip

Use `wasm-strip` from wabt for release-only — drops the Wasm "name" custom section that's only useful for debugging. Small win (1-3%) but real, and breaks nothing in release.

Skip this for dev (DWARF + names are useful when debugging).

### The reflection wall

The largest single Swift-WASM size lever available is `-disable-reflection-metadata`. It strips the runtime metadata used by `Mirror`, key paths, and reflective lookups. Often shaves 20-40% of a Swift WASM.

**We can't use it.** Swiflow's `@State` wrapper uses `Mirror` to enumerate properties on a `Component` instance at mount time. That's how `count += 1` triggers a re-render without explicit `setState` calls. The whole reactivity story breaks if reflection metadata is gone.

Removing this wall is a real lever — and one of the highest-impact bundle-size moves available — but it's an API redesign (probably: `@State` becomes a macro that emits explicit get/set accessor pairs alongside the property, replacing the Mirror-based wiring), not a compile-flag tweak. It belongs on the post-1.0 punch-list as **the** bundle-size move we'd make if we ever wanted to be order-of-magnitude smaller.

The audit doc should call this out explicitly so future-us has the breadcrumb.

### Target

Trim B1 brings the **first-visit** bundle from 20.6 MB gzipped to **13-15 MB gzipped**. Update `docs/perf/bundle-baseline.json` after each landed change. The CI bundle-size gate (Phase 14a) keeps us honest about regression.

---

## Track 3 — Progress UI (B4)

### What ships

When the WASM is downloading on a first visit (no cache, or before the service worker is registered), the user sees a real download percentage rather than a blank screen.

**Mechanism:**

- The driver intercepts the WASM fetch with `fetch(url).then(r => r.body.getReader()...)`, summing bytes as the stream lands.
- After each chunk, the driver writes the current percent to `document.documentElement.dataset.swiflowProgress` (or to a user-marked `[data-swiflow-progress]` element if present).
- The user CSS-styles the progress display. We do not ship UI chrome.

**For repeat visits** (service worker cache hit), the WASM lands instantly; the progress attribute jumps to 100 and the page renders. No flash, no spinner.

### Service worker integration

When the service worker is fetching the WASM during its install phase (i.e., visit #1, post-registration), it `postMessage`s progress to the page so the same `[data-swiflow-progress]` mechanism works there too. Single API, two implementations.

### What the user does

`swiflow init`'s template `index.html` ships:

```html
<style>
  [data-swiflow-progress]:not([data-swiflow-progress="100"])::before {
    content: "Loading " attr(data-swiflow-progress) "%";
    /* user customizes from here */
  }
</style>
```

A user who wants a fancier loading experience styles `[data-swiflow-progress]` however they like. A user who wants nothing strips the CSS. We provide a hook, not a component.

---

## Ordering

Track 1 (service worker) ships first. It's the biggest UX lever and depends on nothing else moving.

Track 2 (trimming) ships second. The audit step is its own deliverable; the compiler/wasm-opt steps land incrementally with `bundle-baseline.json` updates per landing.

Track 3 (progress UI) ships third. It folds naturally into the fetch interception we'll already have in flight from Track 1.

Each track is its own commit + CHANGELOG entry. The whole phase doesn't have to land in one shot.

---

## Success criteria

| Track | Verification |
|---|---|
| B2 | Visit #2 to a Swiflow site transfers <10 KB (manifest only). DevTools shows `App.wasm` served `from ServiceWorker`. After a Swift-source edit, only `App.wasm` re-downloads; runtime cache hit. |
| B1 | `docs/perf/bundle-baseline.json` `total_gzip_bytes` drops ≥20% from the Phase 14a baseline (20.6 MB → ≤16.5 MB). The CI gate continues to pass for the new baseline. |
| B4 | First-visit users see a continuously-updating progress percentage from 0 → 100 during the WASM fetch. Repeat visits jump to 100 within ~100ms. |

---

## Open questions

1. **`wasm-opt` distribution.** Recommendation is "require system install + ship `swiflow doctor` to check." Alternative: vendor binaries per platform. The vendoring path means a much larger CLI release and license/signing work; deferring it feels right.

2. **Cross-origin WASM.** A user who hosts the WASM on a CDN at a different origin from their HTML loses service-worker caching. We document the constraint and don't try to solve it pre-1.0. Most early deploys are single-origin static hosts. If this becomes a felt pain point, we can add a same-origin proxy story.

3. **Should the audit doc include the `--disable-reflection-metadata` measurement?** I.e., actually build the WASM with reflection disabled (knowing `@State` will break) just to record the achievable lower bound. Probably yes — useful future-us breadcrumb — but it adds an extra step to the audit deliverable.

4. **Concurrent first-visit users hitting the service-worker install.** A user who triggers an install on visit #1 and navigates away mid-install needs the next visit to either resume or restart cleanly. Standard service-worker patterns handle this, but we should verify with a flaky-network test scenario in the implementation plan.

---

## Out of scope

- Anything that requires SSG, hydration, or a Swift→HTML serializer. That's a different phase.
- Anything that changes the Swift API surface. `@State`, `@Component`, the DSL all stay exactly as today.
- WASM module sharing across pages or tabs. Service worker caches per-origin; shared-array-buffer / cross-tab caches are a 1.x feature if ever.
- Removing the reflection wall. That's `@State` redesign, post-1.0.
