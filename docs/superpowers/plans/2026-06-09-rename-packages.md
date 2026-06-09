# Rename Swiflow Packages Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename two SwiftPM library modules — `SwiflowHTTP → SwiflowFetcher` and `SwiflowWeb → SwiflowDOM` — across the manifest, sources, tests, examples, generated templates, CI, and live docs, with the build + test suite staying green throughout.

**Architecture:** A Swift module name is load-bearing in only two places: `import X` lines and `Package.swift` (product/target/path). It does **not** ripple through type references, because these modules expose the `Swiflow` namespace enum, not a type named after the module. So each rename is: `git mv` the directory → scoped token replace of the old name → regenerate the embedded-templates file (it is generated from `examples/`, never hand-edited) → fix CI's path guard → fix live docs → build + test. The two renames are independent and land as **two separate commits** on one branch.

**Tech Stack:** Swift 6 / SwiftPM, BSD `sed`/`grep` (macOS), the repo's `scripts/embed-templates.swift` codegen, swiftwasm toolchain (for the optional example smoke build — see `[[wasm-toolchain-setup]]`).

---

## Decisions baked into this plan

These were settled during scoping — they are not open questions:

1. **Two commits, not one.** `SwiflowHTTP → SwiflowFetcher` first (smaller, lower risk), then `SwiflowWeb → SwiflowDOM`. Easier to review and revert independently.
2. **Live docs get updated; historical records do not.** Update `README.md`, `CHANGELOG.md`, `docs/guides/**`, `docs/perf/**`, `docs/compare/**`. **Leave `docs/superpowers/plans/**` and `docs/superpowers/specs/**` untouched** — they are accurate point-in-time records of work done under the old names. (~290 of the 544 `SwiflowWeb` hits live in that historical tree; rewriting them would falsify history for zero functional gain.)
3. **Never hand-edit `Sources/SwiflowCLI/EmbeddedTemplates.swift`.** It carries a `// GENERATED FILE — do not edit` banner and is reproduced from `examples/*/` by `scripts/embed-templates.swift`. A freshness test (`TemplateEmbedderTests`) fails if it drifts. We update `examples/`, then regenerate.
4. **The bare token is safe to replace globally (within scoped dirs).** `SwiflowWeb` only ever appears as the exact module name. `SwiflowHTTP` appears as both the module and as the prefix of `SwiflowHTTPTests` — and we *want* that test target renamed too, so a token replace does the right thing.

## What is NOT being renamed

`Swiflow` (core), `SwiflowMacrosPlugin`, `SwiflowRouter`, `SwiflowQuery`, `SwiflowUI`, `SwiflowTesting`, `SwiflowCLI` — untouched. The `Swiflow` namespace enum (used at every call site as `Swiflow.render`, `div { }`, etc.) is untouched. The devtools (`devtools/`) reference `window.__swiflow`, not Swift module names — untouched and unaffected.

---

## File-touch map

### Task 1 — `SwiflowHTTP → SwiflowFetcher`

| File | Change |
|---|---|
| `Package.swift` | `.library` product (L16), target `name`/`path` (L107/L112), test target `name`/`dependencies`/`path` (L161–163) |
| `Sources/SwiflowHTTP/` → `Sources/SwiflowFetcher/` | directory rename (`git mv`) |
| `Tests/SwiflowHTTPTests/` → `Tests/SwiflowFetcherTests/` | directory rename (`git mv`) |
| `Tests/.../JSONValueTests.swift` | `import SwiflowHTTP` |
| `examples/TodoCRUD/Sources/App/App.swift` | `import SwiflowHTTP` |
| `examples/TodoCRUD/Package.swift` | `.product(name: "SwiflowHTTP", …)` + a comment |
| `Sources/SwiflowCLI/EmbeddedTemplates.swift` | **regenerated**, not edited |
| `CHANGELOG.md`, `docs/future-work/**` | live-doc prose |

### Task 2 — `SwiflowWeb → SwiflowDOM`

| File | Change |
|---|---|
| `Package.swift` | `.library` product (L12), target `name`/`path` (L54/L61) |
| `Sources/SwiflowWeb/` → `Sources/SwiflowDOM/` | directory rename (`git mv`) |
| `Sources/SwiflowWeb/SwiflowWeb.swift` → `Sources/SwiflowDOM/SwiflowDOM.swift` | namespace-anchor file rename (cosmetic but consistent) |
| 13 `examples/**/*.swift` + 8 `examples/**/Package.swift` | `import` + `.product(name:)` |
| `Tests/SwiflowCLITests/DevServer/CompilerBypassTests.swift` | `import SwiflowWeb` |
| `Sources/Swiflow/**` | ~5 doc-comment mentions (cosmetic, keeps comments honest) |
| `.github/workflows/ci.yml` | **L128 grep path `Sources/SwiflowWeb` (load-bearing)** + L117 comment |
| `Sources/SwiflowCLI/EmbeddedTemplates.swift` | **regenerated**, not edited |
| `README.md`, `CHANGELOG.md`, `docs/guides/**`, `docs/perf/**`, `docs/compare/**` | live-doc prose |

---

## A note on method (why there are no "failing tests" here)

This is a **behavior-preserving rename**, not a feature. There is nothing new to test-drive. The safety net is the *existing* green build + test suite: if any reference is missed, `swift build` fails to resolve the module or `swift test` fails (the template freshness test and the CLI compile-a-sample test are the sharp edges that catch a half-done rename). Each task therefore ends with build-green + test-green gates before its commit.

---

## Task 0: Branch

**Files:** none (git only)

- [ ] **Step 1: Confirm clean tree on main**

Run: `git status --short && git rev-parse --abbrev-ref HEAD`
Expected: no output from `status` (clean), branch prints `main`.

- [ ] **Step 2: Create the working branch**

```bash
git checkout -b chore/rename-packages
```

Expected: `Switched to a new branch 'chore/rename-packages'`

---

## Task 1: Rename `SwiflowHTTP → SwiflowFetcher`

**Files:** see Task 1 row of the file-touch map above.

- [ ] **Step 1: Rename the source and test directories**

```bash
git mv Sources/SwiflowHTTP Sources/SwiflowFetcher
git mv Tests/SwiflowHTTPTests Tests/SwiflowFetcherTests
```

Expected: no output (success). `git status` shows the renames staged.

- [ ] **Step 2: Update `Package.swift`**

Replace every `SwiflowHTTP` token (product name, target name + path, test-target name + dependency + path). The token only appears in these six spots:

```bash
sed -i '' 's/SwiflowHTTP/SwiflowFetcher/g' Package.swift
```

Verify exactly six lines changed and they read sensibly:

Run: `git grep -n 'SwiflowFetcher' -- Package.swift`
Expected: product `.library(name: "SwiflowFetcher", targets: ["SwiflowFetcher"])`, target `name: "SwiflowFetcher"` / `path: "Sources/SwiflowFetcher"`, and test target `name: "SwiflowFetcherTests"` / `dependencies: ["SwiflowFetcher"]` / `path: "Tests/SwiflowFetcherTests"`.

- [ ] **Step 3: Update the non-generated import sites (tests + example)**

`SwiflowHTTP` is a distinctive token; replace it across Sources/Tests/examples but **exclude the generated templates file** (regenerated in Step 5):

```bash
grep -rl --exclude='EmbeddedTemplates.swift' 'SwiflowHTTP' Sources Tests examples \
  | xargs sed -i '' 's/SwiflowHTTP/SwiflowFetcher/g'
```

Verify the live import + example manifest were rewritten:

Run: `git grep -n 'SwiflowFetcher' -- Tests/SwiflowFetcherTests examples/TodoCRUD`
Expected: `import SwiflowFetcher` in `JSONValueTests.swift` and `App.swift`; `.product(name: "SwiflowFetcher", package: "Swiflow")` and the updated comment in `examples/TodoCRUD/Package.swift`.

- [ ] **Step 4: Confirm no stray `SwiflowHTTP` remains outside historical docs**

Run: `git grep -n 'SwiflowHTTP' -- . ':!docs/superpowers'`
Expected: only `CHANGELOG.md` and `docs/future-work/**` (handled in Step 6) and the still-stale generated `EmbeddedTemplates.swift` (handled in Step 5). No hits in `Sources/Swiflow*`, `Tests`, `examples`, or `Package.swift`.

- [ ] **Step 5: Regenerate the embedded templates**

```bash
swift scripts/embed-templates.swift
```

Expected: the script rewrites `Sources/SwiflowCLI/EmbeddedTemplates.swift` from the now-updated `examples/`. Verify it picked up the rename and the banner is intact:

Run: `git grep -c 'SwiflowFetcher' -- Sources/SwiflowCLI/EmbeddedTemplates.swift && head -1 Sources/SwiflowCLI/EmbeddedTemplates.swift`
Expected: a non-zero count, and the first line is `// GENERATED FILE — do not edit.` Confirm zero `SwiflowHTTP` remain there: `git grep -c 'SwiflowHTTP' -- Sources/SwiflowCLI/EmbeddedTemplates.swift` → `0` (grep exits non-zero / prints nothing).

- [ ] **Step 6: Update live docs (leave `docs/superpowers/**`)**

```bash
sed -i '' 's/SwiflowHTTP/SwiflowFetcher/g' CHANGELOG.md
grep -rl 'SwiflowHTTP' docs/future-work | xargs sed -i '' 's/SwiflowHTTP/SwiflowFetcher/g'
```

Run: `git grep -n 'SwiflowHTTP' -- . ':!docs/superpowers'`
Expected: **no output** — every live reference now says `SwiflowFetcher`; only the historical `docs/superpowers/**` tree still mentions the old name (intentional).

- [ ] **Step 7: Build**

Run: `swift build`
Expected: `Build complete!` with no unresolved-module errors.

- [ ] **Step 8: Test (whole suite — catches template drift + CLI scaffolding)**

Run: `swift test`
Expected: all tests pass. In particular `TemplateEmbedderTests` (freshness) and `SwiflowFetcherTests` resolve and pass. If `TemplateEmbedderTests` fails, Step 5 was skipped or `examples/` still holds an old reference — re-run Steps 3 and 5.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "refactor: rename SwiflowHTTP module to SwiflowFetcher

Renames the library product, target, test target, source + test
directories, and all import sites. Regenerates EmbeddedTemplates.swift
from the updated examples. Live docs updated; historical
docs/superpowers records left under the old name intentionally.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: Rename `SwiflowWeb → SwiflowDOM`

**Files:** see Task 2 row of the file-touch map above.

- [ ] **Step 1: Rename the source directory and the namespace-anchor file**

```bash
git mv Sources/SwiflowWeb Sources/SwiflowDOM
git mv Sources/SwiflowDOM/SwiflowWeb.swift Sources/SwiflowDOM/SwiflowDOM.swift
```

Expected: no output (success). There is no `Tests/SwiflowWebTests` directory to move (the renderer is exercised through `SwiflowTests`/`SwiflowCLITests`), so do not attempt one.

- [ ] **Step 2: Update `Package.swift`**

```bash
sed -i '' 's/SwiflowWeb/SwiflowDOM/g' Package.swift
```

Run: `git grep -n 'SwiflowDOM' -- Package.swift`
Expected: product `.library(name: "SwiflowDOM", targets: ["SwiflowDOM"])`, target `name: "SwiflowDOM"` / `path: "Sources/SwiflowDOM"`. (No test-target lines — `SwiflowWeb` had none of its own.)

- [ ] **Step 3: Replace the token across sources, tests, and examples**

Excludes the generated templates file (regenerated in Step 6). This rewrites: the moved module's internal `// Sources/SwiflowWeb/...` path comments, ~5 doc comments in `Sources/Swiflow/**`, `CompilerBypassTests.swift`, all 13 example `.swift` imports, and all 8 example `Package.swift` `.product(name:)` refs:

```bash
grep -rl --exclude='EmbeddedTemplates.swift' 'SwiflowWeb' Sources Tests examples \
  | xargs sed -i '' 's/SwiflowWeb/SwiflowDOM/g'
```

Run: `git grep -c 'import SwiflowDOM' -- examples | head` and `git grep -n 'SwiflowDOM' -- examples/HelloWorld/Package.swift`
Expected: each example app file imports `SwiflowDOM`; `examples/HelloWorld/Package.swift` shows `.product(name: "SwiflowDOM", package: "Swiflow")`.

- [ ] **Step 4: Update CI's Foundation-free guard (LOAD-BEARING)**

`.github/workflows/ci.yml` greps the literal path `Sources/SwiflowWeb`. If this is not updated, the guard greps a path that no longer exists, finds nothing, and **silently passes** — quietly stopping its protection of this module against `import Foundation`. Update both the grep path and its explanatory comment:

```bash
sed -i '' 's/SwiflowWeb/SwiflowDOM/g' .github/workflows/ci.yml
```

Run: `git grep -n 'SwiflowDOM' -- .github/workflows/ci.yml`
Expected: two lines — the comment listing runtime modules and the `Sources/SwiflowDOM` path inside the `grep -rn "^import Foundation$"` block.

- [ ] **Step 5: Confirm no stray `SwiflowWeb` remains outside historical docs + generated file**

Run: `git grep -n 'SwiflowWeb' -- . ':!docs/superpowers'`
Expected: only `Sources/SwiflowCLI/EmbeddedTemplates.swift` (Step 6) and the live docs `README.md` / `CHANGELOG.md` / `docs/guides/**` / `docs/perf/**` / `docs/compare/**` (Step 7). No hits in `Sources/Swiflow*`, `Tests`, `examples`, `Package.swift`, or `.github/`.

- [ ] **Step 6: Regenerate the embedded templates**

```bash
swift scripts/embed-templates.swift
```

Run: `git grep -c 'SwiflowWeb' -- Sources/SwiflowCLI/EmbeddedTemplates.swift`
Expected: `0` (no output). The file now references `SwiflowDOM`, reproduced from the updated `examples/`.

- [ ] **Step 7: Update live docs (leave `docs/superpowers/**`)**

```bash
for f in README.md CHANGELOG.md; do sed -i '' 's/SwiflowWeb/SwiflowDOM/g' "$f"; done
grep -rl 'SwiflowWeb' docs/guides docs/perf docs/compare | xargs sed -i '' 's/SwiflowWeb/SwiflowDOM/g'
```

Run: `git grep -n 'SwiflowWeb' -- . ':!docs/superpowers'`
Expected: **no output** — only the historical `docs/superpowers/**` tree retains the old name (intentional).

- [ ] **Step 8: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 9: Test (whole suite)**

Run: `swift test`
Expected: all pass. `TemplateEmbedderTests` (freshness) and `CompilerBypassTests` (compiles a generated sample that now imports `SwiflowDOM`) are the ones that would catch a missed reference — both green.

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "refactor: rename SwiflowWeb module to SwiflowDOM

Renames the library product, target, source directory, and namespace
anchor file; updates all import sites, example manifests, the CI
Foundation-free path guard, and live docs. Regenerates
EmbeddedTemplates.swift from the updated examples. Historical
docs/superpowers records left under the old name intentionally.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: End-to-end smoke (optional but recommended)

A host `swift build`/`swift test` proves the library graph and the CLI's compile-a-sample path, but the **examples** only truly compile under the swiftwasm toolchain. Run one real scaffold + build to prove the renamed modules link in WASM. Requires the matched swiftwasm toolchain — see `[[wasm-toolchain-setup]]`.

**Files:** none (runtime verification).

- [ ] **Step 1: Build an example to WASM**

```bash
cd examples/HelloWorld && swiflow build
```

Expected: a successful WASM build (no `no such module 'SwiflowDOM'` / `'SwiflowFetcher'`). Return with `cd -` afterward.

- [ ] **Step 2: Scaffold a fresh project from the renamed templates**

`swiflow init` takes a project *name* plus `--path` (parent dir). Two things matter here: run the **freshly-built** CLI via `swift run` so it embeds the just-regenerated templates, and pass `--swiflow-source "$(pwd)"` so the generated project depends on this local renamed clone (without it, the scaffold pins to a published release that still has the old module names). Run from the repo root:

```bash
swift run swiflow init rename-smoke --path /tmp --swiflow-source "$(pwd)"
(cd /tmp/rename-smoke && swiflow build)
```

Expected: the generated `/tmp/rename-smoke/Package.swift` references `SwiflowDOM` (and `SwiflowFetcher` if that template uses it) and builds cleanly — proving `EmbeddedTemplates.swift` regenerated correctly. Clean up: `rm -rf /tmp/rename-smoke`.

---

## Task 4: Finish

- [ ] **Step 1: Final reference sweep**

Run: `git grep -n -E 'SwiflowWeb|SwiflowHTTP' -- . ':!docs/superpowers'`
Expected: **no output.** Any hit here is a miss — fix it before finishing.

- [ ] **Step 2: Use `superpowers:finishing-a-development-branch`**

Verify tests pass, then choose merge / PR / keep / discard per that skill. The branch holds exactly two commits (one per rename), already reviewable independently.

---

## Appendix: generalized recipe for renaming any Swiflow module

To rename `SwiflowFoo → SwiflowBar` later, the same shape applies:

1. `git mv Sources/SwiflowFoo Sources/SwiflowBar` (and `Tests/SwiflowFooTests` if it has its own test target; and the `SwiflowFoo.swift` anchor file if one exists).
2. `sed -i '' 's/SwiflowFoo/SwiflowBar/g' Package.swift`.
3. `grep -rl --exclude='EmbeddedTemplates.swift' 'SwiflowFoo' Sources Tests examples | xargs sed -i '' 's/SwiflowFoo/SwiflowBar/g'`.
4. If the module is named in `.github/workflows/ci.yml` (e.g. the Foundation-free path guard), update it there too — a stale grep path fails open.
5. `swift scripts/embed-templates.swift` to regenerate `EmbeddedTemplates.swift` (never hand-edit it).
6. Update live docs; leave `docs/superpowers/**` historical records alone.
7. `swift build && swift test`; sweep `git grep -E 'SwiflowFoo' -- . ':!docs/superpowers'` for stragglers; commit.

**Gotchas, ranked by how much time they cost if missed:**

- **`EmbeddedTemplates.swift` is generated** — hand-editing it (or forgetting to regenerate) fails `TemplateEmbedderTests` with a confusing "drift" message. Update `examples/`, then run the embed script.
- **`ci.yml` greps a literal `Sources/<Module>` path** for the Foundation-free guard — it fails *open*, so a missed update is invisible locally and silently drops a real protection.
- **Module name ≠ namespace.** Call sites use the `Swiflow` enum, not the module name, so renaming the module never touches type references — but it also means the compiler won't flag a missed *doc comment*; only `import` and `Package.swift` misses break the build.
- **`SwiflowHTTP` is a prefix of `SwiflowHTTPTests`** — a bare-token replace renames the test target too, which is what you want. Watch for similar prefix relationships with other names.
