# Runtime JS: minify, mode-aware emission, SW rename — design

**Date:** 2026-06-23
**Status:** Approved, ready for implementation plan

## Problem

A scaffolded Swiflow project carries up to four unminified JavaScript files
at its root, alongside `index.html` and the user's Swift source:

| File | Size | Realm | Used by |
|------|------|-------|---------|
| `swiflow-driver.js` | ~30 KB | main thread (classic script) | every project |
| `swiflow-sw.js` | ~7 KB | service worker | every project |
| `swiflow-regions.js` | ~11 KB | main thread (ES module) | region projects |
| `swiflow-region-guest.js` | ~4 KB | Web Worker (per region) | region projects |

Three distinct issues:

1. **Dead weight on plain projects.** `ProjectWriter.writeProject` currently
   writes **all four** files into *every* project, including non-region
   templates (e.g. HelloWorld). A plain project ships ~15 KB of region JS it
   never loads.
2. **Nothing is minified.** Production builds serve the full unminified
   runtime (~52 KB for a region project).
3. **Inconsistent lifecycle.** `driver` + `sw` are re-emitted on every
   `dev`/`build` (the CLI owns them as generated artifacts). `regions` +
   `guest` are written once at `init` and never refreshed — so they can't be
   varied per mode.

A secondary irritation: `swiflow-sw.js` is an unclear name (`sw` reads
ambiguously against `swiflow`).

## Goals

- Production (`swiflow build`) serves **minified** runtime JS.
- Development (`swiflow dev`) serves **readable** runtime JS (debuggable HMR).
- Plain projects carry **2** runtime files; region projects carry **4**.
- The shipped `swiflow` CLI binary stays **Node-free** — minification happens
  at embed/codegen time, baked into `EmbeddedDriver.swift` as string constants.
- Rename `swiflow-sw.js` → `swiflow-service-worker.js` for clarity.

## Non-goals

- **Bundling into a single file.** Architecturally impossible: the service
  worker must be a separate top-level script (spec), and the region guest runs
  in its own Web Worker realm via dynamic `import()`. The realistic floor is
  2 files (plain) / 3–4 files (region), not 1.
- **Relocating files into a subdirectory.** Decided against: moving
  `swiflow-sw.js` out of the root narrows its control scope to that
  subdirectory unless served with a `Service-Worker-Allowed: /` header, which
  plain static hosts (GitHub Pages, S3) often can't set — the SW would silently
  stop controlling the page. Files stay at the project root.
- **Source maps.** They add files, working against the cleanup goal. The
  readable source of truth lives in `js-driver/` and git.

## Architecture

Three coordinated pieces.

### Piece 1 — Minify at embed time (Node-free CLI)

`scripts/embed-driver.swift` already reads the four readable `js-driver/*.js`
files and bakes them into `Sources/SwiflowCLI/EmbeddedDriver.swift`. Extend it
to also produce a **minified** variant of each, so `EmbeddedDriver` exposes
**eight** constants:

```
javascriptSource          / javascriptSourceMinified
serviceWorkerSource       / serviceWorkerSourceMinified
regionsSource             / regionsSourceMinified
guestSdkSource            / guestSdkSourceMinified
```

Minification tool: **esbuild**, added as a `js-driver` `devDependency` and
invoked from the embed script (the script shells out to the local
`node_modules/.bin/esbuild`). Per-file minify, **no bundling**:

- `swiflow-driver.js`, `swiflow-sw.js` — classic scripts, default format.
- `swiflow-regions.js` — `--format=esm` (it's an ES module).
- `swiflow-region-guest.js` — `--format=esm` (imported as a module in the
  worker).

Constraints:

- **Pin the exact esbuild version** in `js-driver/package.json`. esbuild output
  can differ across versions; a floating version would make the embed codegen
  non-deterministic and break the byte-equality tests across machines/CI.
- **No property-name mangling** (esbuild default). The region postMessage
  protocol keys (`kind`, `payload`, `v`, …) and any property names read by name
  must survive. Only local-variable mangling / whitespace removal is safe.
- The minified constants are **never** copied into the tracked example
  projects — examples keep the readable variant (they are dev-like and must
  stay debuggable). The byte-equality test continues to compare example copies
  against the **readable** embedded constants only.

### Piece 2 — Unify all four as regenerated, mode-aware artifacts

Make `regions` + `guest` behave like `driver` + `sw`: owned by the CLI,
re-emitted on every `dev`/`build`, **readable in dev, minified in build**, and
emitted **only when the project uses regions**.

**Region-usage detection.** A project uses regions iff its `index.html`
references `swiflow-regions.js` (region templates carry
`<script type="module" src="swiflow-regions.js"></script>`; plain templates do
not). The installer reads `index.html` and emits the region pair only on a
match. This is the single source of truth for "is this a region project" —
no separate flag or manifest field.

**Mode-aware variant selection.**

- `swiflow dev`  → write the **readable** variants.
- `swiflow build` → write the **minified** variants.

**Installer shape.** `DriverInstaller.install` (today writes `driver` + `sw`)
gains a `minified: Bool` parameter and additionally writes the region pair when
`index.html` references the regions script:

```
DriverInstaller.install(into: projectDir, minified: Bool)
  always:        swiflow-driver.js, swiflow-service-worker.js
  if regions:    swiflow-regions.js, swiflow-region-guest.js
  variant:       readable when minified == false, minified when true
```

`dev` calls `install(into:, minified: false)`; `build` calls
`install(into:, minified: true)` (and continues to stamp the service worker
build tag — see `installStamped`, which must also pick the minified variant in
build).

**Init.** `ProjectWriter.writeProject` stops unconditionally writing the
region pair. It writes:

- `swiflow-driver.js` + `swiflow-service-worker.js` — always (readable; a fresh
  scaffold is dev-first).
- `swiflow-regions.js` + `swiflow-region-guest.js` — only when the selected
  template's `index.html` references the regions script.

Because `dev`/`build` now re-emit the region pair, the init-time write is just
a convenience for the first load; the source of truth for which files exist is
the per-mode installer.

**Net result:**

| Project type | Files at root | dev | build |
|--------------|---------------|-----|-------|
| Plain | `driver`, `service-worker` (+ html, Swift) | readable | minified |
| Region | `driver`, `service-worker`, `regions`, `region-guest` | readable | minified |

### Piece 3 — Rename `swiflow-sw.js` → `swiflow-service-worker.js`

Mechanical rename across all references:

- `js-driver/swiflow-sw.js` → `js-driver/swiflow-service-worker.js` (the source
  file itself).
- `js-driver/swiflow-driver.js` — the SW registration call
  `navigator.serviceWorker.register("swiflow-sw.js")` and the stale-SW
  unregister guard `endsWith("/swiflow-sw.js")` → new name.
- `scripts/embed-driver.swift` — input path + header comment.
- `Sources/SwiflowCLI/EmbeddedDriver.swift` — regenerated by the script.
- `DriverInstaller` / `ProjectWriter` — output filename(s).
- `TemplateEmbedder.blacklist` — `"swiflow-sw.js"` entry → new name.
- The **6 vendored example copies** (`examples/*/swiflow-sw.js`) → renamed, and
  their contents kept byte-equal to the readable embedded SW.
- `js-driver/test/*` — any test referencing the old filename.

**Migration note (accepted):** an already-deployed `swiflow-sw.js` service
worker on a user's site will not be auto-unregistered by the renamed worker's
stale-SW guard (which now looks for `swiflow-service-worker.js`). Pre-1.0 this
is acceptable; users can hard-reload or unregister manually. No migration shim.

## Data flow

```
js-driver/*.js  (readable source of truth, hand-edited)
      │
      │  scripts/embed-driver.swift
      │    ├─ read 4 readable files
      │    └─ esbuild --minify (pinned) → 4 minified strings
      ▼
EmbeddedDriver.swift   (8 string constants: readable + minified × 4)
      │
      ├─ ProjectWriter (init)      → readable driver+sw always; readable
      │                              regions+guest iff template uses regions
      ├─ DriverInstaller (dev)     → readable, region pair iff index.html uses it
      └─ DriverInstaller (build)   → minified, region pair iff index.html uses it
```

## Testing

- **Embed determinism / freshness.** The existing embed-freshness test
  (`EmbeddedDriver.swift` matches a fresh run of the codegen) extends to cover
  the minified constants. Requires the pinned esbuild to be installed in CI's
  `js-driver/node_modules`; if esbuild is unavailable, the codegen must fail
  loudly rather than silently emit unminified bytes as the "minified" variant.
- **Byte-equality (examples).** Unchanged in intent: the 6 vendored example
  copies stay byte-equal to the **readable** embedded constants, now under the
  renamed `swiflow-service-worker.js`.
- **Region-usage detection.** Unit-test the predicate that decides region
  emission from `index.html` contents: positive (contains the regions
  `<script>`), negative (plain page), and robustness (commented-out reference,
  differing whitespace/quotes) — pick and document one matching rule.
- **Mode selection.** Test that `dev` writes readable and `build` writes
  minified (assert on a cheap, stable marker — e.g. presence of newlines /
  length delta — rather than exact minified bytes, to avoid pinning the test to
  an esbuild version).
- **Minified correctness smoke.** A node:test that loads the minified driver +
  regions and exercises a representative path (e.g. the region postMessage
  envelope round-trip) to confirm minification didn't break the wire protocol.
- **No region JS on plain projects.** Assert a plain-template scaffold does
  **not** contain `swiflow-regions.js` / `swiflow-region-guest.js`.

## Risks & mitigations

- **esbuild version drift → non-deterministic embed.** Mitigation: pin exact
  version; embed script fails if the binary is missing or the version differs.
- **Minifier breaks the wire protocol.** Mitigation: no property mangling +
  the minified-correctness smoke test.
- **Renamed SW orphans old workers.** Accepted pre-1.0; documented above.
- **CI lacks esbuild.** Mitigation: `js-driver` install step (already present
  for the driver tests) brings esbuild in via `devDependencies`; the embed
  freshness check runs after `npm ci`.

## Out of scope / possible follow-ups

- Gitignoring the generated runtime files in user projects (since `dev`/`build`
  regenerate them) — a further decluttering step, deferred.
- A migration shim that unregisters the old `swiflow-sw.js` — deferred,
  pre-1.0.
