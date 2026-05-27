# Phase 16 — Foundation-Free Runtime

**Status:** Draft (spec)
**Author:** Alain Duchesneau
**Date:** 2026-05-27
**Predecessor:** [Phase 15 — Pre-1.0 Dependency Diet](./2026-05-26-phase15-dependency-diet-design.md)

---

## 1. Goal

Make every runtime module — `Swiflow`, `SwiflowRouter`, `SwiflowWeb` — contain **zero `import Foundation` statements**, and add a CI guard that enforces the invariant so it cannot rot.

Host-side modules (`SwiflowCLI`, `SwiflowMacrosPlugin`) are out of scope: they execute on macOS/Linux, never ship in the WASM binary, and freely use Foundation for filesystem, process, JSON, and SwiftSyntax glue work.

## 2. Why this matters

Phase 15 removed the *transitive* Foundation dependency that came through Mirror's reflection metadata. What remains in the runtime are two **direct** `import Foundation` statements:

1. `Sources/SwiflowRouter/Core/RouteMatching.swift` — uses `String.removingPercentEncoding` in `splitQuery(_:)` to decode URL query keys and values.
2. `Sources/SwiflowWeb/HMR/HMRBridge.swift` — `import Foundation` exists but no Foundation symbol is referenced in the source (a comment mentions NSNumber while explaining a JSObject cast). Apparently vestigial; verify empirically.

The **primary win is architecture hygiene, not bundle size**. After Phase 15, Foundation is no longer the dominant cost — Swift stdlib + JavaScriptKit is. `removingPercentEncoding` is a small stdlib-string method; removing it will not move the bundle measurably. We measure to be honest about that, not to chase headlines.

What it *does* buy us:

- **A grep-enforceable invariant.** `grep -rn "^import Foundation" Sources/Swiflow Sources/SwiflowRouter Sources/SwiflowWeb` must return zero hits. The next contributor who casually adds `import Foundation` to a runtime file gets a CI failure with a clear message instead of silently expanding the dependency surface.
- **A clean story for the 1.0 announcement.** "The Swiflow runtime depends on the Swift standard library and JavaScriptKit. Nothing else." reads better than "...mostly, except for two leftover Foundation imports we never got around to removing."
- **A foundation (pun intended) for future bundle work.** Once Foundation is provably absent from the runtime, the *next* lever — JavaScriptKit bridge slimming — has a clean baseline to compare against.

## 3. Architecture

### 3.1 The work

Two source-file edits and one CI-config edit:

| File | Change |
|---|---|
| `Sources/SwiflowRouter/Core/RouteMatching.swift` | Drop `import Foundation`. Replace two `removingPercentEncoding` call sites with a private file-local `percentDecode(_:)` helper that matches Foundation's semantics exactly. |
| `Sources/SwiflowWeb/HMR/HMRBridge.swift` | Try dropping `import Foundation` directly. If the build succeeds (expected), commit. If a symbol turns out to need it, root-cause and decide per case. |
| `.github/workflows/ci.yml` | Add a `Verify Foundation-free runtime` step to the `test` job, run before any compile step so violations fail fast and cheaply. |

### 3.2 Why inline, not a shared helper

`percentDecode(_:)` lives directly in `RouteMatching.swift` as a `private` function. It is not promoted to `package` or `public`, and it does not live in a new shared module.

Rationale:

- **One caller.** YAGNI — don't preemptively expose a helper before a second user exists. This is the exact pattern Phase 15 set with `URLSanitizer`'s file-local `matches`/`matchesCaseInsensitive` decoders.
- **No risk of API drift.** Internal callers cannot accidentally couple to a published API contract.
- **Easy to hoist later.** If a second caller appears (e.g., a future `URLSearchParams`-style API or a server-side decoder shared with the CLI), promotion to `package`-scope in `Swiflow` is a five-minute move.

### 3.3 Why a new decoder and not URLSanitizer's helpers

`URLSanitizer.decodeHTMLColonEntities(_:)` decodes a **different** thing: HTML colon entities (`&#58;`, `&#x3a;`) inside string-typed URL values bound for `href`/`src`. It is not a general percent-decoder. Sharing would conflate two unrelated decoders that happen to scan strings; keep them separate.

## 4. Detailed design — `percentDecode`

### 4.1 Semantics (must match `String.removingPercentEncoding`)

| Input shape | Foundation behavior | Our behavior |
|---|---|---|
| No `%` in string | Returns `Optional(input)` (always succeeds) | Same — fast path returns `s` unchanged |
| `%` followed by two ASCII hex digits | Decode byte; accumulate; final UTF-8 validate | Same |
| `%` not followed by two hex chars (e.g., `hello%2G`, `hello%`) | Returns `nil` | Returns `nil` |
| Bytes accumulate to invalid UTF-8 (e.g., lone continuation byte) | Returns `nil` | Returns `nil` (via `String(validating:as:)`) |
| Hex case (`%c3%a9` vs `%C3%A9`) | Both accepted | Both accepted |
| `+` character | Left as `+` (RFC 3986) | Left as `+` (matches Foundation) |
| `%00` (NUL byte) | Decodes to a literal NUL | Decodes to a literal NUL |

**`+` is deliberately NOT translated to space.** WHATWG `URLSearchParams` and HTML form encoding do translate `+` to space; RFC 3986 does not, and Foundation's `removingPercentEncoding` follows RFC 3986. Switching to WHATWG semantics is a separate behavior decision that should be discussed on its own merits, not bundled into a Foundation-removal patch.

### 4.2 Implementation

```swift
/// RFC 3986 percent-decoder for query keys and values.
/// Returns `nil` for any malformed `%XX` sequence or invalid UTF-8 —
/// matches `String.removingPercentEncoding` semantics so callers can
/// keep the existing `?? original` fallback in `splitQuery(_:)`.
///
/// `+` is preserved as a literal `+` (RFC 3986). WHATWG / HTML form
/// `+` → space translation is out of scope and would be a separate
/// behavior change.
private func percentDecode(_ s: String) -> String? {
    guard s.contains("%") else { return s }   // fast path
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
private func hexDigit(_ b: UInt8) -> UInt8? {
    switch b {
    case 0x30...0x39: return b - 0x30           // '0'-'9'
    case 0x41...0x46: return b - 0x41 &+ 10     // 'A'-'F'
    case 0x61...0x66: return b - 0x61 &+ 10     // 'a'-'f'
    default: return nil
    }
}
```

Notes:

- `String(validating: bytes, as: UTF8.self)` (Swift 6.0+, available in 6.3) returns `nil` for invalid UTF-8. This is the strict-match behavior; `String(decoding: bytes, as: UTF8.self)` would substitute U+FFFD and never fail, which would diverge from Foundation.
- `&+` (overflow-trapping arithmetic disabled) is used on the `b - 0x41 &+ 10` and `b - 0x61 &+ 10` paths because the inputs are pre-validated by the case range — overflow is impossible and `&+` matches the stdlib style for byte-twiddling hot paths.
- `s.contains("%")` fast path is O(n) but avoids buffer allocation when the common case (no encoding) holds.

### 4.3 Call site swap

```swift
// Before
let key = String(parts[0]).removingPercentEncoding ?? String(parts[0])
let value = String(parts[1]).removingPercentEncoding ?? String(parts[1])

// After
let key = percentDecode(String(parts[0])) ?? String(parts[0])
let value = percentDecode(String(parts[1])) ?? String(parts[1])
```

The `?? String(parts[0])` fallback is preserved character-for-character so behavior under malformed input is identical.

## 5. `HMRBridge.swift` — opportunistic cleanup

Inspection shows `import Foundation` on line 16 but no Foundation symbol referenced in the source. The only Foundation mention is in a comment explaining a JSObject coercion:

```swift
// NSNumber and `v as? Int` succeeds for Bool values.
```

This is a comment about a quirk the *code* handles, not a use of Foundation. The import is most likely a vestigial leftover from an earlier draft.

**Approach:** simply remove the import and recompile. Two outcomes:

- **Build succeeds (expected).** Commit the removal.
- **Build fails.** A symbol does need Foundation. Surface the symbol, look at it, and choose between (a) a stdlib swap, (b) a JavaScriptKit equivalent, or (c) keeping the import with a one-line justification comment so future cleanup attempts don't waste cycles. Decide per case; do not pre-plan a swap for a need that may not exist.

## 6. Tests

Existing test coverage in `Tests/SwiflowRouterTests/RouteMatchingTests.swift` exercises the no-percent path (`?q=swift&page=2`). New tests are **regression guards**, not red-green drivers — they pass against the current Foundation-backed implementation, get committed first, and then prove still-green against the stdlib implementation.

Add the following cases (suggested addition site: the existing `query` test group in `RouteMatchingTests.swift`, or a sibling test function `testQueryPercentDecoding` if the existing group is structurally tight):

| # | URL fragment | Expected `query` map |
|---|---|---|
| T1 | `?q=hello%20world` | `["q": "hello world"]` |
| T2 | `?q=caf%C3%A9` | `["q": "café"]` |
| T3 | `?q=swift%20%2B%20wasm` | `["q": "swift + wasm"]` (verifies `%2B` round-trip → `+`) |
| T4 | `?q=%c3%a9` | `["q": "é"]` (lowercase hex) |
| T5 | `?caf%C3%A9=val` | `["café": "val"]` (encoded key) |
| T6 | `?q=hello%` | `["q": "hello%"]` (lone `%`, fallback to original) |
| T7 | `?q=hello%2G` | `["q": "hello%2G"]` (bad hex, fallback to original) |
| T8 | `?q=swift+wasm` | `["q": "swift+wasm"]` (asserts `+` is NOT translated to space — documents the RFC 3986 choice) |

T8 is important: it locks in the deliberate semantic choice. If someone later wants WHATWG `+` → space, T8 will fail and the change will be explicit.

## 7. CI guard

Add a step to the `test` job in `.github/workflows/ci.yml`, placed before the `Build library + WebTarget` step so violations fail fast (the grep is sub-second; failing here prevents wasting compile time on a contribution that violates the invariant):

```yaml
      - name: Verify Foundation-free runtime
        # The runtime modules (Swiflow, SwiflowRouter, SwiflowWeb) ship
        # in the WASM binary. Importing Foundation there risks pulling
        # back the reflection / demangler / SIMD cost that Phase 15
        # cut by 90%. Host-side modules (SwiflowCLI, SwiflowMacrosPlugin)
        # are not gated — they run on macOS/Linux, never in the browser.
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

Failure mode tested by temporarily adding `import Foundation` to a runtime file and confirming the CI step fails with the expected error message. Revert before commit.

## 8. Bundle measurement

Re-run `scripts/measure-bundle.sh` against `examples/HelloWorld` after the Foundation removal. Update `docs/perf/bundle-baseline.json` **only if the delta exceeds the noise floor** (more than ~5 KB gzipped, the rough variance observed across consecutive measurements on the same source). If the delta is below noise, append a one-line outcome to `docs/perf/2026-05-26-wasm-bundle-audit.md` under a "Phase 16" subhead: "No measurable bundle change (within noise). Win is architectural, not size."

This is the honest framing. Phase 15 already drained Foundation's transitive cost via Mirror removal; whatever stdlib-bridge surface `removingPercentEncoding` pinned is small.

## 9. Phasing (4 tasks)

Each task ends with a commit. Tasks are small enough that subagent-driven execution should not need multiple review iterations per task.

### Task 1 — Regression-guard tests

Add the 8 test cases from §6 to `Tests/SwiflowRouterTests/RouteMatchingTests.swift`. Run `swift test --filter SwiflowRouterTests` (or the project's standard test command) and confirm **all 8 new tests pass against the current Foundation-backed implementation**. Commit.

Title shape: `test(router): regression guards for query percent-decoding`

### Task 2 — Drop Foundation from RouteMatching.swift

Add the `percentDecode` and `hexDigit` helpers at the bottom of `Sources/SwiflowRouter/Core/RouteMatching.swift`. Replace the two `removingPercentEncoding` call sites in `splitQuery(_:)`. Remove the `import Foundation` line. Run the full Swift test suite and confirm green; the 8 new tests from Task 1 specifically must still pass. Commit.

Title shape: `refactor(router): drop Foundation; inline stdlib percent-decoder`

### Task 3 — Try dropping Foundation from HMRBridge.swift, plus CI guard

Two changes in one commit because they prove the invariant together:

1. Remove `import Foundation` from `Sources/SwiflowWeb/HMR/HMRBridge.swift`. Build. If the build fails, surface the symbol, decide (per §5), and either swap or keep with a one-line justification comment.
2. Add the `Verify Foundation-free runtime` CI step to `ci.yml` per §7.

Commit only after both pass locally (a manual `grep -rn "^import Foundation" Sources/Swiflow*` should produce zero hits before commit).

Title shape: `chore(web): drop vestigial Foundation import; gate runtime in CI`

### Task 4 — Measure, document, ship

Run `scripts/measure-bundle.sh`. Compare against `docs/perf/bundle-baseline.json`. If delta exceeds 5 KB gzipped, update the baseline; otherwise leave it. Append a Phase 16 entry to `docs/perf/2026-05-26-wasm-bundle-audit.md` with whatever the measurement actually showed (honest framing). Add a CHANGELOG entry under "Unreleased" titled "Phase 16 — Foundation-Free Runtime" with: Changed (the two file edits), Added (the CI guard), Bundle (the measured delta), Test changes (T1-T8 added). Commit. Push.

Title shape: `docs: Phase 16 — Foundation-Free Runtime shipped`

## 10. Out of scope

Explicitly **not** part of this phase:

- **`+` → space translation.** That is a routing-semantics decision, not a Foundation-removal decision. T8 documents the choice.
- **JavaScriptKit bridge slimming.** Multi-quarter, post-1.0. Tracked in the audit doc's "Remaining levers" section.
- **Foundation removal from `SwiflowCLI` / `SwiflowMacrosPlugin`.** These run on the host, never in the WASM binary. Foundation is appropriate there.
- **A shared percent-decoder helper.** Inline is fine for one caller. Hoist if and when a second caller appears.
- **A unified URL-parsing layer.** The current `splitQuery` + `RoutePattern.match` is enough; designing a fuller URL parser is a separate piece of work that should be motivated by a user need, not preemptively for code-purity reasons.

## 11. Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| `String(validating:as:)` API surface differs in the WASM 6.3 SDK vs. host Swift 6.3 | Low | The WASM SDK ships the same stdlib as the host; verify by running the regression tests via `swift test`, which already exercises stdlib-only paths used in WASM. |
| `HMRBridge.swift` actually needs Foundation for a symbol grep missed (e.g., a `Date` formatter via type inference) | Low | Build fails immediately on import removal; root-cause and decide per §5. Worst case: keep the import with a one-line comment explaining why. |
| The CI grep flags a legitimate `import Foundation` inside a comment or doc string | Very low | The anchor `^import Foundation` only matches lines that begin with the literal import statement, not commented or indented occurrences. |
| Tests T6/T7 (fallback for malformed input) pass against current Foundation impl for the wrong reason — e.g., Foundation accepts something we don't | Low | The `?? original` fallback masks any divergence on the failure branch. If Foundation accepts a sequence our decoder rejects, the call still returns the original literal; behavior is identical to the user. Document this in the test comments. |
| Bundle delta is genuinely negative (size grows) | Very low | If a measurement shows growth > noise floor, do not commit; investigate the call-site that's now pulling extra symbols. Probably means `String(validating:as:)` pinned something `removingPercentEncoding` did not. Report and decide. |

## 12. Self-review checklist

- [x] Placeholder scan — no TBD, no "implement later", no vague requirements
- [x] Internal consistency — `percentDecode` signature matches between §4.2, §4.3, and §6; CI guard regex (`^import Foundation`) matches the lines being protected against
- [x] Scope check — 4 small tasks, single subsystem, one focused session
- [x] Ambiguity check — `+` semantics explicitly chosen (RFC 3986, not WHATWG); fallback behavior on malformed input explicitly preserved; HMRBridge cleanup explicitly "try and decide"
- [x] Honest framing — bundle win is not promised, only measured

---

End of spec.
