# Swiflow Phase 4 — Hardening Design

> **Status:** Approved 2026-05-19. Next step: writing-plans turns this spec into an executable task list.
>
> **Predecessor:** Phase 3 (Reactivity) shipped end-to-end including browser-verified smoke test of the Counter demo. Live at `origin/main`. CI green.

## 1. Goal

Harden Swiflow before Phase 5 (HMR, component library, etc.) lands more features on top. The bet: catching framework footguns early and closing the explicitly-listed XSS surface pays compounding dividends as more feature code arrives.

This is not a release-readiness phase. The original spec's §7 mentioned 9 candidate Phase 4 directions; we are deliberately deferring distribution (Homebrew tap, NPM driver publish), `swiflow build --production`, and performance optimizations (LIS keyed diff, binary patch buffer). They reappear when there are real users to justify them.

## 2. Scope (4 items)

| # | Item | One-line | Effort |
|---|---|---|---|
| 1 | **URL sanitizer** | Strip `javascript:` from `href`/`src`/`action`; configurable scheme allowlist. | Small (~80 LOC) |
| 2 | **Diagnostic errors** (debug-only) | Runtime `fatalError` + clear message for duplicate keys, mixed keyed/unkeyed children, component body cycles. | Medium (~200 LOC) |
| 3 | **Source maps spike** | 2-hour timebox investigation whether `.wasm.map` files beat the existing DWARF + Chrome C/C++ extension flow. Conditional follow-up. | Investigation; +0–150 LOC |
| 4 | **Test expansion (minimal)** | `node:test`+`jsdom` units for the 14 JS driver opcodes; one Playwright happy-path spec for the Counter demo. | Large (~400 LOC + Node toolchain) |

Total estimate: ~900 LOC + a one-off spike. 4 SDD-shaped tasks; expected wall time similar to Phase 3.

## 3. Out of scope

Explicitly deferred to a later phase:
- `swiflow build --production` (wasm-opt + gzip + DWARF strip)
- Homebrew tap + release pipeline
- NPM driver publish (`@swiflow/driver`)
- Keyed diff LIS optimization
- Binary patch buffer (`Uint8Array` over linear memory)
- Perf benchmarks in CI (needs baseline first)
- Cross-browser Playwright (Firefox/WebKit)
- Visual regression / screenshot diffing
- JS driver coverage reporting

## 4. Item 1 — URL sanitizer

**Why first:** smallest, no dependencies, closes a real XSS hole the security spec explicitly listed.

### 4.1 Threat model

Any framework attribute that the browser interprets as a URL is a potential code-execution vector if user-controlled input lands in it unsanitized:

| Attribute | Risk |
|---|---|
| `<a href="javascript:...">` | Click executes |
| `<img src>`, `<script src>`, `<iframe src>`, `<source src>`, `<video src>`, `<audio src>` | Browser fetches/executes |
| `<form action>`, `<button formaction>`, `<input formaction>` | Submit posts |

### 4.2 Default allowlist

`http`, `https`, `mailto`, `tel`, `ftp`, plus relative URLs and fragment-only (`#foo`). Everything else → sanitized.

### 4.3 Sanitization behavior

When a URL fails the allowlist:
- Drop the value entirely
- Emit a debug-mode diagnostic via the §5 Diagnostics layer
- Skip the patch (don't emit `setAttribute`)

Don't replace with `about:blank` or `#` — that masks the developer error. Skipping is loud (the link doesn't work) without breaking the page.

### 4.4 Opt-out / extension

```swift
// Defaults at module load:
Swiflow.urlSanitizer.allowedSchemes = ["http", "https", "mailto", "tel", "ftp"]
Swiflow.urlSanitizer.allowDataURLs = false  // rare; security-sensitive
Swiflow.urlSanitizer.allowBlobURLs = false
```

Mutating after `Swiflow.render(_:into:)` is undefined behavior. A `precondition(!hasRendered)` in the setter enforces this.

### 4.5 Where the check fires

At the DSL boundary (`.href(...)`, `.src(...)`, etc. modifiers), not in the patch emitter or the JS driver. Rationale:
- Earliest possible — failed sanitization detected before any patch is built
- Doesn't slow the diff hot path
- Easy to audit — every `.href(_:)`-style call site is a sanitization site
- `VNode.rawHTML("...")` remains the intended escape hatch for cases the sanitizer rejects

### 4.6 Files

- New: `Sources/Swiflow/Reactivity/URLSanitizer.swift` — `URLSanitizer` enum with `static func sanitize(_ value: String, for context: AttributeContext) -> String?` (nil = reject)
- Modify: `Sources/Swiflow/DSL/Modifiers.swift` — `.href`, `.src`, `.action`, `.formaction` route through the sanitizer
- Modify: `Sources/SwiflowWeb/SwiflowWeb.swift` — expose `Swiflow.urlSanitizer` config namespace
- New: `Tests/SwiflowTests/Reactivity/URLSanitizerTests.swift` — table-driven coverage including obfuscation attacks (case, whitespace, HTML entities)

### 4.7 Edge cases tested

- `javascript:alert(1)` — rejected
- `JAVASCRIPT:alert(1)` — rejected (case-insensitive)
- `\tjavascript:alert(1)` — rejected (leading whitespace stripped before scheme check)
- `javascript&#58;alert(1)` — rejected (HTML entities decoded before check)
- `mailto:user@example.com` — accepted
- `#section-2` — accepted (fragment-only)
- `/path/to/page` — accepted (relative)
- `https://example.com` — accepted
- `data:text/html;base64,...` — rejected by default; accepted when `allowDataURLs = true`

## 5. Item 2 — Diagnostic errors (debug-only)

**Why second:** catches its own bugs while implementing items 3 + 4, and every future feature thereafter. Wins compound.

### 5.1 Approach

`#if DEBUG`-guarded `fatalError` calls at the framework's known footgun points. Zero runtime cost in release builds. React-style.

### 5.2 What gets checked

| Check | Where | Today | After |
|---|---|---|---|
| **Duplicate keys** among siblings | `diffChildren` keyed path; set-walk pre-pass | Last-write-wins on the Map; produces wrong moves silently | `fatalError("Duplicate key 'X' among siblings of <div>. Keys must be unique within a parent. Offending positions: 2 and 5.")` |
| **Mixed keyed/unkeyed siblings** | `diffChildren` dispatch | Falls into keyed path; unkeyed children get unstable identity, rerender as recreated | `fatalError("Children of <ul> mix keyed (3) and unkeyed (2) entries. Either key every child or key none.")` |
| **Component body anchor cycle** | `mount()` / `update()` `.component` path; depth guard | Infinite recursion → stack overflow | `fatalError("Component <Counter>'s body returned a VNode.component anchor cycle (depth > 32). Bodies must terminate at non-component VNodes.")` |

The fourth originally-considered check ("attribute on non-element") is structurally impossible — only `VNode.element` carries attribute bags — so it's skipped.

### 5.3 Files

- New: `Sources/Swiflow/Reactivity/Diagnostics.swift` — central `swiflowDiagnostic(_ message:)` helper, all `#if DEBUG`-guarded. Single entry point so the build-mode logic lives in one place.
- Modify: `Sources/Swiflow/Diff/Diff.swift` — call diagnostic helpers from `diffChildren` dispatcher and `mount()` `.component` arm
- Modify: `Sources/Swiflow/Diff/KeyedChildrenDiff.swift` — duplicate-key detection (a `Set<String>` walk before the 2-pointer scan)
- New: `Tests/SwiflowTests/Reactivity/DiagnosticsTests.swift` — for each check, verify the `fatalError` fires in DEBUG with the expected message substring

### 5.4 Design notes

- Use `fatalError`, not `assert` or `precondition` — must crash hard even if someone toggles `-O` while keeping `DEBUG=1`. The `#if DEBUG` guard is what gives the release-mode skip.
- Message convention: framework concept first ("Duplicate key"), then location/cause ("among siblings of `<div>`"), then guidance ("Keys must be unique within a parent. Offending positions: 2 and 5."). React-style.
- Recursion-depth guard: trampoline counter passed through `mount()`, max depth 32 (already absurd; cycles always exceed).
- Tests use Swift Testing 6.0's exit-test API: `await #expect(processExitsWith: .failure) { … }` wrapped around the offending call. The closure runs in a subprocess; the parent test observes the crash signal. Message-substring matching is via reading the subprocess's stderr capture. If a check turns out to be expensive or non-deterministic to test this way, an alternative is to factor the diagnostic predicate into a pure boolean function and test that directly, then keep only one exit-test per check as a smoke test.

## 6. Item 3 — Source maps spike

**Investigation, not implementation.** Two-hour timebox; outcome determines follow-up scope.

### 6.1 Question

Does shipping `.wasm.map` source maps give a meaningfully better debugging experience than what we already have (DWARF symbols in dev builds + Chrome's C/C++ DevTools extension)?

### 6.2 Probes

1. Does Chrome's stock DevTools (no extension) read `.wasm.map`?
   - Build a tiny WASM with `wasm-emit-sourcemap`, attach via `<script type="application/wasm">`, set a breakpoint, see if Sources panel shows Swift.
2. Does the PackageToJS plugin emit `.wasm.map`?
   - `swift package js --help` + grep the plugin sources for source-map flags.
3. Is there a Swift→`.wasm.map` toolchain step we're missing?
   - Check `wasm-opt --debuginfo` output; check `wasm-objdump`; verify whether Apple's WASM SDK emits one when DWARF is requested.
4. What's the current end-to-end debugging story?
   - Boot the Counter demo, trigger a deliberate trap (`fatalError("test")` in body), inspect DevTools — does the Chrome extension flow actually map back to Swift?

### 6.3 Decision matrix

| Spike outcome | Follow-up |
|---|---|
| Source maps add nothing over DWARF | Skip Phase 4 source maps. Write `docs/debugging-wasm.md` documenting the DWARF flow (install Chrome C/C++ ext, enable, point at .wasm). |
| Source maps work but require a manual `wasm-emit-sourcemap` step | Add a CLI flag `swiflow build --emit-source-maps` + toolchain wiring + docs. ~150 LOC. |
| Source maps work natively via the SDK | Wire into `BuildInvocation` for dev builds (mirroring how `--debug-info-format dwarf` was wired). ~30 LOC + docs. |

### 6.4 Files (provisional, depends on outcome)

- Always: `docs/debugging-wasm.md` (final form depends on which flow we recommend)
- Conditional: `Sources/SwiflowCLI/Commands/BuildCommand.swift` modifications
- Conditional: `scripts/emit-source-maps.swift` if a separate tooling step is needed

No commit until the spike answers the question. The implementation plan branches accordingly.

## 7. Item 4 — Test expansion (minimal)

**Why last:** biggest commitment; benefits from items 1 + 2 being already validated.

Two new test layers, both Node-based, both opt-in (existing `swift test` is unaffected).

### 7.1 JS driver units (`node:test` + `jsdom`)

Unit tests for each of the 14 opcodes in `js-driver/swiflow-driver.js`, plus the reload-WebSocket dev-mode logic. Today the only JS driver test is the Phase 2c e2e (which requires a full WASM build cycle); a bug in `removeChild`'s map cleanup or `addHandler`'s key formatting is invisible to Swift tests because Swift owns the patch SIDE, not the consume side.

```
js-driver/
├── swiflow-driver.js              # source of truth (unchanged)
├── package.json                   # NEW — declares jsdom + node:test deps
├── README.md                      # already exists
└── test/                          # NEW
    ├── helpers.js                 # jsdom setup, applyPatches helper
    ├── opcodes.test.js            # 14 opcode tests
    └── dev-reload.test.js         # WebSocket reload handler test
```

Run via `cd js-driver && npm install && npm test`. `npm test` aliases to `node --test test/`.

Touch surface: ~250 LOC tests, ~30 LOC for `package.json` + helpers.

### 7.2 Playwright happy-path e2e

One Playwright spec that drives the Counter demo end-to-end in headless Chromium:

```
tests/playwright/
├── package.json                   # NEW — declares @playwright/test
├── playwright.config.ts           # NEW — webServer = `swiflow dev`
├── README.md                      # NEW — how to run locally
└── counter.spec.ts                # NEW — the test
```

The test asserts: page renders the Counter, clicking increments visibly, two clicks → "Count: 2". One test, Chromium-only. Firefox/WebKit coverage is Phase 5+. The single spec proves the toolchain holds; future tests inherit the harness for free.

Touch surface: ~150 LOC including setup helpers, plus Playwright's browser binaries downloaded by `npx playwright install`.

### 7.3 CI integration

| Job | Trigger | Runner | Expected runtime |
|---|---|---|---|
| Existing `Test (ubuntu-22.04)` | push + PR | ubuntu-22.04 | unchanged (~5 min cached) |
| NEW `JS Driver Tests` | push + PR | ubuntu-22.04 | ~30s (npm install + node test) |
| NEW `Playwright E2E` | **PR only** | ubuntu-22.04 | ~5 min (cached) |

Playwright runs on PRs only — same reasoning as macOS (gates expensive setups behind the merge boundary). Both new jobs use the cheap Linux runner; zero macOS multiplier.

## 8. Ordering and execution

| # | Task | Pause point? |
|---|---|---|
| 1 | URL sanitizer | — |
| 2 | Diagnostic errors | **🛑 Pause for user review** — at this point the user-facing hardening is shipped; rest is internal investment. |
| 3 | Source maps spike (2h timebox) | — |
| 4 | Source maps follow-up (conditional, depends on spike) | — |
| 5 | JS driver units (`node:test` + jsdom) | — |
| 6 | Playwright e2e (Counter happy path) | — |

**SDD per task:** implementer → spec compliance reviewer → code quality reviewer → fix-up if needed → next.

**Commit convention:** one commit per task using `feat(<scope>): ...` / `fix(...)` / `docs(...)` / `test(...)` prefixes. Co-Authored-By trailer: `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>`.

## 9. Risk register

| Risk | Mitigation |
|---|---|
| Source-maps spike rabbit-holes | 2-hour hard timebox. If unresolved at 2h, skip the source-maps follow-up entirely and document DWARF-only. |
| Playwright adds Node dependency + Chromium binaries to CI | Node is preinstalled on `ubuntu-22.04`; `npx playwright install --with-deps chromium` adds ~3 min to first cache-miss run, cached afterward. GHA cache key includes `npm-shrinkwrap.json` hash. |
| `node:test` requires Node 18+ | `setup-node@v4` action handles this. Pin to Node 20 LTS. |
| Diagnostic errors leak into production via toggled DEBUG flag | `#if DEBUG` is bound to SwiftPM's `-c debug`/`-c release` switch. Belt-and-suspenders: a unit test invokes a known-diagnostic-firing path in a `-c release` build and asserts no crash. |
| URL sanitizer breaks legitimate `data:image/png;base64,...` uses | `Swiflow.urlSanitizer.allowDataURLs = true` opt-in. Documented in the URLSanitizer doc comment with explicit "rare; security-sensitive — use only when source is trusted" warning. |
| Browser-binary download in CI exceeds GitHub Actions cache (5GB limit) | Playwright cache is ~300MB per browser; one browser → fits easily. If we ever add Firefox/WebKit, switch to a separate cache key per browser. |

## 10. Success criteria

Phase 4 is done when:

- [ ] `swiflow init demo` projects pass `swift test` AND `npm test` (JS driver) AND `npx playwright test`.
- [ ] An intentionally-introduced duplicate-key bug fires a clear `fatalError` in debug builds and is invisible in release builds.
- [ ] `<a href="javascript:alert(1)">` produces no patch and surfaces a diagnostic in debug builds.
- [ ] The source-maps decision is documented (either as wired CLI flag or as a `docs/debugging-wasm.md` recommending DWARF).
- [ ] CI on `main` runs the new test layers; the Playwright job runs on PRs.
- [ ] All commits land on `origin/main` with a Co-Authored-By trailer.

## 11. Next step

Invoke the `superpowers:writing-plans` skill to turn this spec into an executable task plan saved at `docs/superpowers/plans/2026-05-19-swiflow-phase4-hardening.md`. Plan execution will follow the SDD pattern (implementer + two-stage review per task) consistent with Phase 3.
