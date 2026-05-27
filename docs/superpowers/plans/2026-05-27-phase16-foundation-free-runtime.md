# Phase 16 — Foundation-Free Runtime Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the two remaining `import Foundation` statements from runtime modules and add a CI guard that prevents regression.

**Architecture:** Replace `String.removingPercentEncoding` in `RouteMatching.swift` with an inline stdlib-only `percentDecode(_:)` helper whose semantics match Foundation exactly (returns `nil` on malformed input or invalid UTF-8). Opportunistically drop the vestigial `import Foundation` from `HMRBridge.swift`. Add a grep-based CI step that fails fast if any runtime module re-imports Foundation.

**Tech Stack:** Swift 6.3, Swift stdlib (`String.utf8`, `String(validating:as:)`), Swift Testing framework, GitHub Actions, `scripts/measure-bundle.sh`.

**Spec:** `docs/superpowers/specs/2026-05-27-phase16-foundation-free-runtime-design.md` (commit `3822d8b`).

---

## File Structure

Files this plan touches (everything else is read-only context):

| File | Change | Responsibility after change |
|---|---|---|
| `Tests/SwiflowRouterTests/RouteMatchingTests.swift` | Modify | Adds 8 regression-guard tests for percent-decoding; pre-existing `query` test stays intact. |
| `Sources/SwiflowRouter/Core/RouteMatching.swift` | Modify | Drops `import Foundation`; gains two private file-local helpers (`percentDecode`, `hexDigit`); `splitQuery(_:)` call sites swap to the new helper. |
| `Sources/SwiflowWeb/HMR/HMRBridge.swift` | Modify (one-line) | Drops the unused `import Foundation`. |
| `.github/workflows/ci.yml` | Modify | Adds a single `Verify Foundation-free runtime` step to the `test` job, placed before any `swift build`. |
| `docs/perf/bundle-baseline.json` | Conditionally modify | Updated **only** if the measured delta exceeds noise floor (~5 KB gzipped). |
| `docs/perf/2026-05-26-wasm-bundle-audit.md` | Append | Adds a Phase 16 outcome subhead with the measured bundle delta. |
| `CHANGELOG.md` | Modify | Adds a Phase 16 entry above Phase 15. |

No file creation. Every change is bounded to a single existing file.

---

## Pre-flight (read before Task 1)

Before any task, confirm the working tree is clean and the project builds:

```bash
git status
swift build
swift test --parallel
```

Expected: `git status` reports a clean tree on `main`. `swift build` succeeds. `swift test --parallel` passes ~537 Swift tests across ~106 suites.

If any of these fail, **stop and investigate**. Do not proceed with Phase 16 on a broken baseline.

---

## Task 1: Regression-Guard Tests for Percent-Decoding

These tests must pass against the **current Foundation-backed implementation** before any production-code changes. They lock in semantics so Task 2's stdlib swap can be verified against an objective spec.

**Files:**
- Modify: `Tests/SwiflowRouterTests/RouteMatchingTests.swift` (append 8 new `@Test` cases to the existing `RouteMatchingTests` suite, after the `queryStringDoesNotBreakMatch` test on line ~64)

- [ ] **Step 1: Add the 8 percent-decoding test cases**

Open `Tests/SwiflowRouterTests/RouteMatchingTests.swift`. Find the `queryStringDoesNotBreakMatch` test (around line 60–64). Immediately after its closing brace, insert this block (before the `nestedRouteMatchesChild` test):

```swift
    @Test("query percent-decoding: ASCII space")
    func queryPercentDecodingASCIISpace() {
        var captured: RouterContext? = nil
        let route = leafCapture("/search", into: &captured)
        _ = matchRoutes([route], path: "/search?q=hello%20world")
        #expect(captured?.query["q"] == "hello world")
    }

    @Test("query percent-decoding: multi-byte UTF-8")
    func queryPercentDecodingUTF8() {
        var captured: RouterContext? = nil
        let route = leafCapture("/search", into: &captured)
        _ = matchRoutes([route], path: "/search?q=caf%C3%A9")
        #expect(captured?.query["q"] == "café")
    }

    @Test("query percent-decoding: encoded plus round-trip")
    func queryPercentDecodingEncodedPlus() {
        var captured: RouterContext? = nil
        let route = leafCapture("/search", into: &captured)
        _ = matchRoutes([route], path: "/search?q=swift%20%2B%20wasm")
        #expect(captured?.query["q"] == "swift + wasm")
    }

    @Test("query percent-decoding: lowercase hex digits")
    func queryPercentDecodingLowercaseHex() {
        var captured: RouterContext? = nil
        let route = leafCapture("/search", into: &captured)
        _ = matchRoutes([route], path: "/search?q=%c3%a9")
        #expect(captured?.query["q"] == "é")
    }

    @Test("query percent-decoding: encoded key")
    func queryPercentDecodingEncodedKey() {
        var captured: RouterContext? = nil
        let route = leafCapture("/search", into: &captured)
        _ = matchRoutes([route], path: "/search?caf%C3%A9=val")
        #expect(captured?.query["café"] == "val")
    }

    // Malformed-escape fallback: Foundation's removingPercentEncoding returns
    // nil on a lone trailing '%', and splitQuery falls back to the literal
    // substring via `?? String(parts[1])`. The stdlib decoder in Task 2 must
    // match this behavior so this assertion survives the swap.
    @Test("query percent-decoding: lone trailing percent falls back to literal")
    func queryPercentDecodingLoneTrailingPercent() {
        var captured: RouterContext? = nil
        let route = leafCapture("/search", into: &captured)
        _ = matchRoutes([route], path: "/search?q=hello%")
        #expect(captured?.query["q"] == "hello%")
    }

    // Bad-hex fallback: '%2G' is not a valid percent escape; both Foundation
    // and the Task 2 stdlib decoder return nil, and splitQuery falls back
    // to the literal substring.
    @Test("query percent-decoding: invalid hex falls back to literal")
    func queryPercentDecodingInvalidHex() {
        var captured: RouterContext? = nil
        let route = leafCapture("/search", into: &captured)
        _ = matchRoutes([route], path: "/search?q=hello%2G")
        #expect(captured?.query["q"] == "hello%2G")
    }

    // Deliberate semantic lock-in: RFC 3986 leaves '+' as a literal '+'.
    // WHATWG URLSearchParams + HTML form encoding translate '+' to space;
    // Swiflow follows Foundation (RFC 3986). If a future change wants to
    // adopt WHATWG semantics, this assertion will fail loudly and the
    // change will be deliberate.
    @Test("query: literal plus stays literal (RFC 3986, not WHATWG)")
    func queryPlusStaysLiteral() {
        var captured: RouterContext? = nil
        let route = leafCapture("/search", into: &captured)
        _ = matchRoutes([route], path: "/search?q=swift+wasm")
        #expect(captured?.query["q"] == "swift+wasm")
    }
```

- [ ] **Step 2: Run the new tests to verify they pass against current Foundation impl**

Run:

```bash
swift test --parallel --filter SwiflowRouterTests.RouteMatchingTests
```

Expected: **All `RouteMatchingTests` tests pass**, including the 8 newly added ones. The pre-existing tests (10 of them) must also stay green.

If any of the 8 new tests fail at this step, the test expectation is wrong (not the production code). Re-check the table in spec §6 — the assertion is the source of truth.

If the *pre-existing* tests start failing, you've accidentally broken the file structure — revert and re-apply the edit cleanly.

- [ ] **Step 3: Commit**

```bash
git add Tests/SwiflowRouterTests/RouteMatchingTests.swift
git commit -m "$(cat <<'EOF'
test(router): regression guards for query percent-decoding

Eight new tests pinning the semantics of String.removingPercentEncoding
as currently used by splitQuery — ASCII space, multi-byte UTF-8,
encoded '+', lowercase hex, encoded key, fallback on lone '%' / bad
hex, and the RFC-3986 choice to leave literal '+' as '+'.

These pass against the current Foundation impl; they exist so Phase 16
Task 2 can swap to a stdlib-only decoder and prove parity.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

Expected: commit succeeds; `git status` clean.

---

## Task 2: Drop Foundation from RouteMatching.swift

Replace `String.removingPercentEncoding` with a private file-local stdlib decoder. Drop `import Foundation`.

**Files:**
- Modify: `Sources/SwiflowRouter/Core/RouteMatching.swift`

- [ ] **Step 1: Replace `import Foundation` line**

Open `Sources/SwiflowRouter/Core/RouteMatching.swift`. On line 2, replace `import Foundation` with nothing — delete the line entirely. The file's import block should now read only:

```swift
// Sources/SwiflowRouter/Core/RouteMatching.swift
import Swiflow
```

- [ ] **Step 2: Replace the two `removingPercentEncoding` call sites**

In `splitQuery(_:)`, find lines 52–53:

```swift
            let key = String(parts[0]).removingPercentEncoding ?? String(parts[0])
            let value = String(parts[1]).removingPercentEncoding ?? String(parts[1])
```

Replace them with:

```swift
            let key = percentDecode(String(parts[0])) ?? String(parts[0])
            let value = percentDecode(String(parts[1])) ?? String(parts[1])
```

The `??` fallback is preserved: if `percentDecode` returns `nil`, the original literal substring is used, matching the prior Foundation behavior exactly.

- [ ] **Step 3: Add `percentDecode` and `hexDigit` helpers**

At the end of the file (after `splitQuery(_:)`'s closing brace on line 58), append:

```swift

/// RFC 3986 percent-decoder for URL query keys and values.
///
/// Returns `nil` for any malformed `%XX` sequence or for byte sequences
/// that do not form valid UTF-8 — matches `String.removingPercentEncoding`
/// semantics exactly, so `splitQuery`'s `?? original` fallback preserves
/// the prior behavior on invalid input.
///
/// `+` is left as a literal `+` (RFC 3986 query semantics). WHATWG
/// URLSearchParams and HTML form encoding translate `+` to space — that
/// is a separate semantic choice tracked by the
/// `queryPlusStaysLiteral` regression test.
private func percentDecode(_ s: String) -> String? {
    guard s.contains("%") else { return s }     // fast path
    var bytes: [UInt8] = []
    bytes.reserveCapacity(s.utf8.count)
    var it = s.utf8.makeIterator()
    while let b = it.next() {
        if b == 0x25 {  // '%'
            guard let h1 = it.next(), let h2 = it.next(),
                  let hi = hexDigit(h1), let lo = hexDigit(h2)
            else { return nil }
            bytes.append((hi << 4) | lo)
        } else {
            bytes.append(b)
        }
    }
    return String(validating: bytes, as: UTF8.self)
}

/// ASCII hex-digit nibble. `nil` for any non-hex byte.
/// `&+` is overflow-trapping arithmetic disabled: the case ranges
/// pre-validate the inputs, so overflow is impossible by construction.
private func hexDigit(_ b: UInt8) -> UInt8? {
    switch b {
    case 0x30...0x39: return b - 0x30           // '0'-'9'
    case 0x41...0x46: return b - 0x41 &+ 10     // 'A'-'F'
    case 0x61...0x66: return b - 0x61 &+ 10     // 'a'-'f'
    default: return nil
    }
}
```

- [ ] **Step 4: Build and confirm the file compiles**

Run:

```bash
swift build
```

Expected: build succeeds.

Most likely failure mode: `String(validating: bytes, as: UTF8.self)` not found. If you see `cannot find 'validating' in scope` or `extra argument 'validating' in call`, the Swift toolchain is older than 6.0. Verify with `swift --version`; the project pins to Swift 6.3 in `.github/workflows/ci.yml`, so this should not happen on the standard developer toolchain. If it does, escalate — the spec's §11 Risks table flagged this as low-probability but possible.

- [ ] **Step 5: Run the full router test suite**

Run:

```bash
swift test --parallel --filter SwiflowRouterTests
```

Expected: **all SwiflowRouterTests pass**, including the 8 Task-1 regression guards. The query-percent-decoding tests are the ones most likely to surface a semantic divergence; if any of them fail, re-read spec §4.1 (the parity table) and compare your `percentDecode` against the cases the failing test exercises.

- [ ] **Step 6: Run the full test suite**

Run:

```bash
swift test --parallel
```

Expected: all ~537 tests pass.

- [ ] **Step 7: Verify Foundation import is gone**

Run:

```bash
grep -n "import Foundation" Sources/SwiflowRouter/Core/RouteMatching.swift
```

Expected: no output (grep exits with status 1, which is what we want).

Also verify the broader runtime grep:

```bash
grep -rn "^import Foundation" Sources/Swiflow Sources/SwiflowRouter Sources/SwiflowWeb
```

Expected: one remaining hit only — `Sources/SwiflowWeb/HMR/HMRBridge.swift`. Task 3 will remove that. No other runtime modules should now import Foundation.

- [ ] **Step 8: Commit**

```bash
git add Sources/SwiflowRouter/Core/RouteMatching.swift
git commit -m "$(cat <<'EOF'
refactor(router): drop Foundation; inline stdlib percent-decoder

splitQuery replaces String.removingPercentEncoding with a private
file-local percentDecode helper. Semantics match Foundation exactly:
returns nil on malformed %XX or invalid UTF-8, callers' ?? fallback
preserves prior behavior on invalid input.

'+' deliberately left as literal '+' (RFC 3986). The
queryPlusStaysLiteral regression test from Task 1 documents the
choice; switching to WHATWG '+'-as-space is a separate behavior call.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: HMRBridge Cleanup + CI Guard

Two changes that prove the invariant together: remove the last `import Foundation` from the runtime, then gate it with a CI step that prevents reintroduction.

**Files:**
- Modify: `Sources/SwiflowWeb/HMR/HMRBridge.swift` (delete one line)
- Modify: `.github/workflows/ci.yml` (add one job step)

- [ ] **Step 1: Try removing `import Foundation` from HMRBridge.swift**

Open `Sources/SwiflowWeb/HMR/HMRBridge.swift`. On line 16, delete the `import Foundation` line. The imports block should now read:

```swift
import JavaScriptKit
import Swiflow
```

- [ ] **Step 2: Build to confirm Foundation was vestigial**

Run:

```bash
swift build
```

**Expected (likely path):** build succeeds. Continue to Step 3.

**Unexpected path:** build fails with "cannot find 'X' in scope" for some Foundation symbol. Inspect the error.

- If the missing symbol is a `Date`, `URL`, `Data`, or similar Foundation type, restore `import Foundation` on line 16 and add a one-line comment above it:

  ```swift
  // Foundation: needed for <SymbolName> on line <N>.
  import Foundation
  ```

  Then **stop and report**: surface the symbol name and which line uses it. The spec's §5 anticipates this and says: decide per case. Do not invent a stdlib replacement without discussion.

- If the missing symbol is something subtle (e.g., a `String` extension Foundation provides), same approach: restore the import, comment it, surface the finding.

- [ ] **Step 3: Run the full test suite**

Run:

```bash
swift test --parallel
```

Expected: all tests still pass. HMR-related tests (`SwiflowTests`, anything touching `HMRBridge`) are the highest-risk surface; if a test fails here, the removed `import Foundation` was *not* in fact vestigial. See Step 2's unexpected-path guidance.

- [ ] **Step 4: Confirm the runtime is Foundation-free**

Run:

```bash
grep -rn "^import Foundation" Sources/Swiflow Sources/SwiflowRouter Sources/SwiflowWeb
```

Expected: no output (grep exits with status 1).

If any hit remains, do not proceed to Step 5 — the CI guard will fail. Re-check the file you just edited.

- [ ] **Step 5: Add the CI guard step to `.github/workflows/ci.yml`**

Open `.github/workflows/ci.yml`. Find the `test` job's `steps:` section. After the `Verify Swift version` step (which appears around line 113–114 as):

```yaml
      - name: Verify Swift version
        run: swift --version
```

…insert this new step **immediately after it** (before `Cache SwiftPM build + WASM SDK`):

```yaml
      - name: Verify Foundation-free runtime
        # The runtime modules (Swiflow, SwiflowRouter, SwiflowWeb) ship in
        # the WASM binary. Importing Foundation there risks pulling back
        # the reflection / demangler / SIMD cost that Phase 15 cut by 90%.
        # Host-side modules (SwiflowCLI, SwiflowMacrosPlugin) run on
        # macOS/Linux only and are not gated.
        run: |
          set -euo pipefail
          if grep -rn "^import Foundation" \
               Sources/Swiflow \
               Sources/SwiflowRouter \
               Sources/SwiflowWeb; then
            echo "::error::Runtime modules must not import Foundation."
            echo "::error::See docs/superpowers/specs/2026-05-27-phase16-foundation-free-runtime-design.md"
            exit 1
          fi
          echo "Runtime modules are Foundation-free."
```

The step is placed before the cache restore so it fails fast — the grep is sub-second; failing here saves the cache restore + compile time on a contribution that violates the invariant.

- [ ] **Step 6: Verify the guard succeeds against the current tree**

Simulate the CI step locally:

```bash
set -euo pipefail
if grep -rn "^import Foundation" \
     Sources/Swiflow \
     Sources/SwiflowRouter \
     Sources/SwiflowWeb; then
  echo "FAIL"; exit 1
fi
echo "PASS"
```

Expected output: `PASS`. Exit code 0.

- [ ] **Step 7: Verify the guard fails against a deliberate violation**

Temporarily add `import Foundation` to a runtime file to confirm the guard catches it. For example:

```bash
echo "import Foundation" >> Sources/Swiflow/Reactivity/HMR.swift
```

Run the same grep loop from Step 6. Expected: grep matches, the script prints `FAIL` and exits 1. (You should see the offending line printed by `grep -n`.)

Then revert:

```bash
git checkout Sources/Swiflow/Reactivity/HMR.swift
```

Re-run Step 6's grep one more time. Expected: `PASS`.

- [ ] **Step 8: Commit**

```bash
git add Sources/SwiflowWeb/HMR/HMRBridge.swift .github/workflows/ci.yml
git commit -m "$(cat <<'EOF'
chore(web): drop vestigial Foundation import; gate runtime in CI

HMRBridge.swift's import Foundation was unreferenced — only a comment
mentioned NSNumber while explaining a JSObject cast. Dropping it
leaves Swiflow / SwiflowRouter / SwiflowWeb completely Foundation-free.

A new 'Verify Foundation-free runtime' CI step (in the test job, before
the cache restore) greps for `^import Foundation` in those three module
roots and fails fast on a hit. Host-side modules (SwiflowCLI,
SwiflowMacrosPlugin) are not gated — they run on macOS/Linux only and
never ship in the WASM binary.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

Expected: commit succeeds. `git status` clean.

---

## Task 4: Measure, Document, Ship

Re-run the bundle measurement to honestly report what Foundation removal actually cost (or gained). Update the audit doc and CHANGELOG. Push.

**Files:**
- Conditionally modify: `docs/perf/bundle-baseline.json` (only if delta exceeds noise floor)
- Append: `docs/perf/2026-05-26-wasm-bundle-audit.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Measure the current bundle**

Run from repo root:

```bash
scripts/measure-bundle.sh
```

Expected: builds the swiflow CLI (if needed), cleans + rebuilds the HelloWorld example, prints a Markdown table, and writes `current-bundle.json`.

Note the values from the printed table:

- `App.wasm` raw bytes and gzipped bytes
- JS runtime total bytes and gzipped bytes
- **Total (gzip)** — the headline number

- [ ] **Step 2: Compare against the Phase 15 baseline**

Read the existing baseline:

```bash
cat docs/perf/bundle-baseline.json
```

Pre-Phase-16 baseline (from the file): `total_gzip_bytes: 1,808,783`.

Read the fresh measurement:

```bash
cat current-bundle.json
```

Compute the delta:

```bash
python3 -c "
import json
old = json.load(open('docs/perf/bundle-baseline.json'))
new = json.load(open('current-bundle.json'))
delta = new['total_gzip_bytes'] - old['total_gzip_bytes']
pct = 100.0 * delta / old['total_gzip_bytes']
print(f'WASM gzip delta:  {new[\"wasm_gzip_bytes\"] - old[\"wasm_gzip_bytes\"]:+,} bytes')
print(f'JS gzip delta:    {new[\"js_gzip_bytes\"] - old[\"js_gzip_bytes\"]:+,} bytes')
print(f'TOTAL gzip delta: {delta:+,} bytes ({pct:+.2f}%)')
"
```

Expected outcome (likely): a small delta, well within ±5 KB gzipped. Possibly negative (small shrink), possibly positive (small grow if `String(validating:as:)` pins symbols Foundation hid).

Write down the exact delta numbers — they go into the audit doc in Step 4.

- [ ] **Step 3: Update `bundle-baseline.json` *only* if delta exceeds 5 KB gzipped**

If `|TOTAL gzip delta| > 5120 bytes`, copy the fresh measurement to the baseline:

```bash
cp current-bundle.json docs/perf/bundle-baseline.json
```

If `|TOTAL gzip delta| ≤ 5120 bytes` (the likely case), **do not modify the baseline**. The baseline is treated as the authoritative Phase 15 number; small noise-floor measurements should not perturb it.

- [ ] **Step 4: Append a Phase 16 outcome section to the audit doc**

Open `docs/perf/2026-05-26-wasm-bundle-audit.md`. At the very end of the file, append:

```markdown


## Phase 16 outcome — 2026-05-27

**Headline:** <total gzip delta from Step 2> bytes (<pct>%). The Swiflow runtime is now completely Foundation-free; a CI grep step enforces the invariant against future contributions.

### What landed

- `Sources/SwiflowRouter/Core/RouteMatching.swift` dropped `import Foundation`. `splitQuery(_:)` now decodes query keys and values via a private file-local `percentDecode(_:)` helper. Semantics match `String.removingPercentEncoding` exactly: returns `nil` on malformed `%XX` or invalid UTF-8, and the `?? original` fallback preserves prior behavior on invalid input.
- `Sources/SwiflowWeb/HMR/HMRBridge.swift` dropped its vestigial `import Foundation` — the only reference to Foundation in the file was a comment explaining a JSObject cast.
- A new `Verify Foundation-free runtime` step in the `test` job of `.github/workflows/ci.yml` greps for `^import Foundation` in the three runtime module roots and fails the build on a hit. The check runs before the cache restore so violations fail in sub-second wall time.

### Why the bundle barely moved

Phase 15 already drained Foundation's transitive cost via Mirror removal. The two remaining `import Foundation` statements at the start of Phase 16 pinned only the small `String.removingPercentEncoding` method and (in HMRBridge) nothing at all. `String(validating:as:)` is a Swift 6.0 stdlib method that does not pin Foundation symbols. The honest framing of this phase is **architecture hygiene, not size**: the runtime is now provably Foundation-free, the invariant is grep-enforceable, and the 1.0 story is cleaner.

### Remaining levers (post-Phase-16)

Unchanged from Phase 15's audit:

- **JavaScriptKit's bridge surface.** Multi-quarter post-1.0 project. Still the dominant residual cost.
- **Swift stdlib's residual size.** Hard to shrink without giving up Swift's expressiveness.
- **Foundation in host-side modules** (`SwiflowCLI`, `SwiflowMacrosPlugin`). These run on macOS/Linux only and never ship in the WASM binary; Foundation is appropriate there and out of scope for any size-focused work.
```

Fill in the placeholder `<total gzip delta from Step 2>` and `<pct>` from your actual measurement (e.g., `−417 bytes (−0.02%)` or `+218 bytes (+0.01%)` — use the exact numbers you wrote down in Step 2).

- [ ] **Step 5: Add a Phase 16 entry to CHANGELOG.md**

Open `CHANGELOG.md`. The Phase 15 entry begins at line ~19 with `## [Phase 15] — 2026-05-26`. **Above** that line (after the introductory paragraphs and the `---` separator), insert a new Phase 16 block. The shape:

```markdown
## [Phase 16] — 2026-05-27

**Foundation-free runtime.** The Swiflow runtime modules (`Swiflow`,
`SwiflowRouter`, `SwiflowWeb`) no longer import Foundation. A new CI
guard prevents reintroduction. No user-visible API changes; query
percent-decoding semantics are byte-for-byte identical to the prior
Foundation-backed implementation.

### Changed
- `Sources/SwiflowRouter/Core/RouteMatching.swift` `splitQuery(_:)` now
  decodes URL query keys and values via a private file-local
  `percentDecode(_:)` helper instead of `String.removingPercentEncoding`.
  Returns `nil` on malformed `%XX` or invalid UTF-8 — same semantics as
  Foundation. The `?? original` fallback in the call sites preserves
  prior behavior on invalid input.
- `Sources/SwiflowWeb/HMR/HMRBridge.swift` dropped its vestigial
  `import Foundation`.

### Added
- `.github/workflows/ci.yml` gains a `Verify Foundation-free runtime`
  step in the `test` job. Greps for `^import Foundation` in the three
  runtime module roots; fails the build on any hit. Runs before the
  cache restore so violations fail in sub-second wall time.
- 8 regression-guard tests in `Tests/SwiflowRouterTests/RouteMatchingTests.swift`
  pinning percent-decoding semantics (ASCII space, multi-byte UTF-8,
  encoded '+', lowercase hex, encoded key, fallback on lone '%' / bad
  hex, and the deliberate RFC 3986 choice to leave literal '+' as '+').

### Bundle
- Total gzipped: <fill in from Step 2 measurement, e.g., "1,808,783 → 1,808,366 bytes (−417 bytes / −0.02%)">.
  The win in this phase is architectural, not size — Phase 15 already
  drained Foundation's transitive cost.

### Stability
- Stable for pre-1.0 usage. No user-facing breaking changes.
```

Fill in the bundle line with the actual measured numbers from Step 2.

- [ ] **Step 6: Run the full test suite one final time**

Run:

```bash
swift test --parallel
```

Expected: all ~537 tests pass. This is a sanity check before committing the docs.

- [ ] **Step 7: Commit**

```bash
git add CHANGELOG.md docs/perf/2026-05-26-wasm-bundle-audit.md
# Only include the baseline if it was actually updated in Step 3:
if ! git diff --quiet docs/perf/bundle-baseline.json; then
  git add docs/perf/bundle-baseline.json
fi
git commit -m "$(cat <<'EOF'
docs: Phase 16 — Foundation-Free Runtime shipped

The runtime is now completely Foundation-free. A CI grep step in the
test job enforces the invariant. Bundle delta is within noise (Phase
15 already drained Foundation's transitive cost via Mirror removal);
the win in this phase is architecture hygiene.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 8: Push to origin/main**

```bash
git push origin main
```

Expected: push succeeds. Run `git log --oneline origin/main..HEAD` and confirm it returns empty (everything is pushed).

---

## Post-flight verification

After Task 4 ships, sanity-check the end state:

```bash
# Runtime is Foundation-free
grep -rn "^import Foundation" Sources/Swiflow Sources/SwiflowRouter Sources/SwiflowWeb
# Expected: no output

# All tests pass
swift test --parallel
# Expected: all ~537 tests pass

# Working tree clean, pushed
git status
git log --oneline origin/main..HEAD
# Expected: clean tree, empty log diff
```

If all three checks pass, Phase 16 is complete.

---

## Self-Review

**Spec coverage (skim of spec sections vs. plan tasks):**

- §1 Goal — covered across all 4 tasks.
- §2 Why this matters — captured in the architecture summary at the top and the audit-doc section in Task 4 Step 4.
- §3.1 The work (3 files + CI) — Tasks 2, 3 cover the source-file changes; Task 3 Step 5 covers the CI.
- §3.2 Inline, not shared — Task 2 Step 3 places `percentDecode` and `hexDigit` as `private` file-local functions, per spec.
- §3.3 New decoder, not URLSanitizer's helpers — separate file-local helper added; no attempt to share.
- §4 `percentDecode` semantics + implementation — Task 2 Step 3 contains the exact code from spec §4.2; Task 2 Step 2 swaps the call sites per spec §4.3.
- §5 HMRBridge cleanup — Task 3 Steps 1–4, including the spec's branch-on-failure logic in Step 2.
- §6 Tests — Task 1 contains all 8 cases from spec §6 (T1–T8) as the regression guards.
- §7 CI guard — Task 3 Step 5 places the step where spec §7 specifies (before the cache restore, after `Verify Swift version`).
- §8 Bundle measurement — Task 4 Steps 1–3 cover the measurement and conditional baseline update.
- §9 Phasing — Task 1 = §9 Task 1, Task 2 = §9 Task 2, Task 3 = §9 Task 3, Task 4 = §9 Task 4. One-to-one match.
- §10 Out of scope — implicit. No tasks attempt out-of-scope work.
- §11 Risks — anticipated in Task 2 Step 4 (`String(validating:)` availability) and Task 3 Step 2 (HMRBridge symbol surprise).

**Placeholder scan:** No "TBD" / "TODO" / "implement later" in any step. The two `<fill in from Step 2>` markers in Task 4 Steps 4 and 5 are *parameterized output*, not placeholder code — they describe exactly which number from Step 2 to insert, in what format.

**Type consistency:** `percentDecode(_:) -> String?` and `hexDigit(_:) -> UInt8?` signatures match between Task 2 Step 3 and the spec §4.2. Test function names in Task 1 are valid Swift identifiers and consistent with the rest of `RouteMatchingTests`. CI step name `Verify Foundation-free runtime` is identical between Task 3 Step 5 and the audit doc reference in Task 4 Step 4.

Plan is consistent with the spec. No gaps surfaced.
