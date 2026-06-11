# Targeted Mediums (Bug-Adjacent) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the three bug-adjacent MEDIUM findings from `docs/reviews/2026-06-10-quality-audit.md` that are genuine latent bugs / user-facing correctness issues AND have a pure, host-testable core.

**Architecture:** Three independent correctness fixes. (1) Guard SwiflowQuery's optimistic-mutation rollback with the existing per-entry `generation` counter so a failed mutation can't clobber a *newer* mutation's value or cancel its repair fetch. (2) Make `JSONValue` serialize non-finite doubles as JSON `null` (matching `JSON.stringify`) instead of emitting invalid `"nan"`/`"inf"`. (3) Percent-decode captured path-segment params in SwiflowRouter, the same way query params are already decoded, via a shared decoder helper.

**Tech Stack:** Swift 6 / Swift Testing. All three have host-compiled, host-testable cores (QueryClient mutation engine, `JSONValue.jsonString`, `RoutePattern` matching) — real TDD, no JSKit-gated guesswork.

**Audit findings cleared (MEDIUM):** Unit 7 "concurrent-mutation rollback can clobber newer state and cancel its repair fetch"; Unit 5 "non-finite doubles produce invalid JSON"; Unit 8 "path params never percent-decoded while query params are".

---

## Environment notes (read first)

- Swift tests: ALWAYS `env -u SWIFLOW_SOURCE swift test`. Suite is **800 tests / 182 suites green** on `main` @ `<current HEAD>` (a `chore:` placeholder-restore commit sits on top of the round-4 merge).
- Branch: `git checkout -b feat/targeted-mediums` from `main`.
- No js-driver / wasm work in this plan → no codegen, no wasm build.
- All three fixes are in host-compiled modules (SwiflowQuery, SwiflowFetcher, SwiflowRouter all build + test on host).

## File structure

| File | Action | Responsibility |
|---|---|---|
| `Sources/SwiflowQuery/QueryClient+Cache.swift` | modify | add `generation(of:)` accessor |
| `Sources/SwiflowQuery/MutationState.swift` | modify | capture generation at optimistic-write; guard rollback by it |
| `Sources/SwiflowFetcher/JSONValue.swift` | modify | non-finite double → `null` |
| `Sources/SwiflowRouter/Core/PercentDecoding.swift` | create | shared `percentDecode` (moved from RouteMatching) |
| `Sources/SwiflowRouter/Core/RouteMatching.swift` | modify | drop the local `percentDecode`/`hexDigit`, use the shared one |
| `Sources/SwiflowRouter/Core/RoutePattern.swift` | modify | decode `.param`/`.wildcard` captures |
| Tests (3 new/extended) | create/modify | one per fix |
| `CHANGELOG.md`, `docs/reviews/2026-06-10-quality-audit.md` | modify | bookkeeping |

---

### Task 1: Generation-guarded optimistic-mutation rollback

**The bug (Unit 7 MEDIUM):** `MutationRuntime.finish`'s failure path does
`for r in rollback.reversed() { client.setQueryData(r.key, r.prior) }`, where
`r.prior` was snapshotted at `beginOptimistic` time. If mutation B writes the
same key (optimistically, or via an invalidation refetch that commits) between
A's begin and A's failure, A's rollback overwrites B's value with the
pre-A snapshot — and `setQueryData` *also cancels B's in-flight repair fetch*
(`QueryClient+Cache.swift`: `entry.inFlight?.cancel()`). The fix uses the
existing per-entry `generation` counter (bumped by every `setQueryData` /
`forceStaleAndRefetch`): A records the generation right after its optimistic
write, and rolls back only if the entry's generation is unchanged — i.e. nobody
superseded the key. If it advanced, A skips the rollback (the newer writer owns
the value; A's stale prior must not resurrect, and B's fetch must not be cancelled).

**Files:**
- Modify: `Sources/SwiflowQuery/QueryClient+Cache.swift`, `Sources/SwiflowQuery/MutationState.swift`
- Test: `Tests/SwiflowQueryTests/MutationRollbackGuardTests.swift` (create; mirror the setup in `Tests/SwiflowQueryTests/MutationOptimismTests.swift` — read it first for how the suite builds a `QueryClient`, a `Mutation`, and a `MutationRuntime`, seeds a cached value, and drives `beginOptimistic`/`finish`)

- [ ] **Step 1: Write the failing tests**

Read `MutationOptimismTests.swift` first. Build the tests on its helpers. Required behaviors (write them as REAL compiling tests using the suite's `Mutation`/`MutationRuntime`/`QueryClient` construction):

```swift
// Tests/SwiflowQueryTests/MutationRollbackGuardTests.swift
import Testing
@testable import SwiflowQuery
@testable import Swiflow

@Suite("Mutation rollback is generation-guarded")
@MainActor
struct MutationRollbackGuardTests {

    // 1. A failed mutation whose optimistic key was SUPERSEDED by a later
    //    write does NOT roll back (the newer value survives).
    @Test func failedRollbackSkipsWhenKeyWasSupersededSinceOptimisticWrite() async {
        // - Seed cache: key K = V0 (the prior).
        // - Mutation A: beginOptimistic writes VA into K (its optimistic edit).
        // - Simulate a later writer: client.setQueryData(K, VB)  // bumps generation
        // - A.finish(...) with a perform that FAILS.
        // - Assert: client.getQueryDataErased(K) == VB  (NOT rolled back to V0).
    }

    // 2. A failed mutation whose key was NOT touched since its optimistic write
    //    DOES roll back to the prior (control — the existing behavior is kept
    //    when no supersession happened).
    @Test func failedRollbackRestoresPriorWhenKeyUntouched() async {
        // - Seed K = V0; A.beginOptimistic writes VA; A.finish fails (no B).
        // - Assert: client.getQueryDataErased(K) == V0.
    }
}
```

Use the suite's existing pattern for a failing `perform` (e.g. a `Mutation` whose
`perform` throws). The two behaviors are the spec; the construction mirrors
MutationOptimismTests.

- [ ] **Step 2: Run to verify failure**

Run: `env -u SWIFLOW_SOURCE swift test --filter MutationRollbackGuardTests`
Expected: test 1 FAILS — without the guard, the rollback clobbers VB back to V0.

- [ ] **Step 3: Add the generation accessor**

In `Sources/SwiflowQuery/QueryClient+Cache.swift`, add to the `extension QueryClient`:

```swift
    /// The entry's current supersede `generation` (bumped by `setQueryData` /
    /// `forceStaleAndRefetch`). `nil` when no entry exists. Used by the
    /// mutation engine to detect whether a key was superseded between an
    /// optimistic write and a rollback.
    package func generation(of key: QueryKey) -> Int? {
        entries[key]?.generation
    }
```

- [ ] **Step 4: Capture generation at optimistic write; guard the rollback**

In `Sources/SwiflowQuery/MutationState.swift`:

Change the rollback element type from `(key: QueryKey, prior: Any?)` to
`(key: QueryKey, prior: Any?, gen: Int?)` in BOTH the `beginOptimistic` return
type and the `finish` parameter type. In `beginOptimistic`, the `.write` case:

```swift
                case .write(let next):
                    client.setQueryData(edit.key, next)
                    // Record the post-write generation so `finish` can detect
                    // whether a LATER write superseded this key before rolling
                    // back (which would otherwise clobber the newer value and
                    // cancel its repair fetch).
                    rollback.append((edit.key, prior, client.generation(of: edit.key)))
```

In `finish`, the `.failure` case:

```swift
        case .failure(let err):
            if let client {
                for r in rollback.reversed() {
                    // Only restore the prior if nothing has superseded this key
                    // since our optimistic write. If the generation advanced, a
                    // newer writer owns the value — rolling back would clobber
                    // it (and cancel its in-flight fetch), so we skip.
                    if client.generation(of: r.key) == r.gen {
                        client.setQueryData(r.key, r.prior)
                    }
                }
            }
            status = .error; error = err
```

Verify the rollback value is threaded opaquely through `MutationHandle.mutate` /
`mutateAsync` (it's passed from `beginOptimistic` to `finish` without
inspection) — the added tuple field needs no change there. If any call site
constructs or destructures the rollback tuple by shape, update it; grep
`rollback` in MutationState.swift to confirm.

- [ ] **Step 5: Run tests**

Run: `env -u SWIFLOW_SOURCE swift test --filter MutationRollbackGuardTests` → both pass.
Run: `env -u SWIFLOW_SOURCE swift test --filter "Mutation"` → existing mutation tests green (the guard is a strict superset: with no supersession, generation matches and rollback runs exactly as before).
Run: `env -u SWIFLOW_SOURCE swift test` → full suite green.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "fix(query): generation-guard optimistic-mutation rollback

A failed mutation rolled back to its pre-mutation snapshot unconditionally,
clobbering a concurrent mutation's newer value for the same key and
cancelling that mutation's repair fetch. Rollback now restores the prior
only when the entry's supersede generation is unchanged since the optimistic
write; if a later writer bumped it, the rollback is skipped. Clears audit
MEDIUM: 'concurrent-mutation rollback can clobber newer state'."
```

---

### Task 2: Non-finite doubles serialize as JSON `null`

**The bug (Unit 5 MEDIUM):** `JSONValue.jsonString`'s `.double` case is
`return String(d)`, so `.double(.infinity)` emits `"inf"` and `.double(.nan)`
emits `"nan"` — both invalid JSON, producing a server-side parse error with no
client diagnostic. JSON has no representation for non-finite numbers;
`JSON.stringify` emits `null` for them. Mirror that.

**Files:**
- Modify: `Sources/SwiflowFetcher/JSONValue.swift`
- Test: `Tests/SwiflowFetcherTests/JSONValueTests.swift` (extend — it already tests `2.5`)

- [ ] **Step 1: Write the failing tests**

Add to `Tests/SwiflowFetcherTests/JSONValueTests.swift` (match its existing
style — read it first):

```swift
    @Test func nonFiniteDoublesSerializeAsNull() {
        #expect(JSONValue.double(.infinity).jsonString == "null")
        #expect(JSONValue.double(-.infinity).jsonString == "null")
        #expect(JSONValue.double(.nan).jsonString == "null")
    }

    @Test func nonFiniteInsideContainersIsNull() {
        #expect(JSONValue.array([.double(.nan), .int(1)]).jsonString == "[null,1]")
        #expect(JSONValue.object(["x": .double(.infinity)]).jsonString == #"{"x":null}"#)
    }

    @Test func finiteDoublesAreUnchanged() {
        #expect(JSONValue.double(2.5).jsonString == "2.5")
        #expect(JSONValue.double(0).jsonString == "0.0")
    }
```

(For `finiteDoublesAreUnchanged`, confirm `String(0.0)` is `"0.0"` on this
toolchain — if the existing `2.5` test uses a different exact form, match it.
The point is finite values keep their current rendering.)

- [ ] **Step 2: Run to verify failure**

Run: `env -u SWIFLOW_SOURCE swift test --filter JSONValueTests`
Expected: `nonFiniteDoublesSerializeAsNull` + `nonFiniteInsideContainersIsNull` FAIL (emit `"inf"`/`"nan"`).

- [ ] **Step 3: Implement**

In `Sources/SwiflowFetcher/JSONValue.swift` `jsonString`, replace the `.double` case:

```swift
        case .double(let d):
            // JSON has no representation for non-finite numbers; mirror
            // `JSON.stringify`, which emits `null` for NaN / ±Infinity. Without
            // this, `String(.nan)` would emit the invalid token `nan`, producing
            // a server-side parse error with no client-side signal.
            return d.isFinite ? String(d) : "null"
```

- [ ] **Step 4: Run tests**

Run: `env -u SWIFLOW_SOURCE swift test --filter JSONValueTests` → all green (incl. the existing escaping tests).
Run: `env -u SWIFLOW_SOURCE swift test` → full suite green.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "fix(fetcher): non-finite doubles serialize as JSON null

JSONValue.double(.nan)/.infinity emitted the invalid tokens \"nan\"/\"inf\",
producing server-side parse errors. They now serialize as null, matching
JSON.stringify. Clears audit MEDIUM: 'non-finite doubles produce invalid JSON'."
```

---

### Task 3: Percent-decode captured path-segment params

**The bug (Unit 8 MEDIUM):** `splitQuery` decodes query keys/values via the
module-private `percentDecode`, but `RoutePattern.matchFull`/`matchPrefix` store
captured path segments raw (`params[name] = parts[i]`). So
`/users/john%20doe` yields `ctx.params["id"] == "john%20doe"` while
`?name=john%20doe` yields `"john doe"` — half the URL gets the decoder, the
other half none. Apply the same decoder to path-segment captures. Extract
`percentDecode` into a shared file so both call sites use the one implementation.

**Files:**
- Create: `Sources/SwiflowRouter/Core/PercentDecoding.swift`
- Modify: `Sources/SwiflowRouter/Core/RouteMatching.swift` (remove local copy), `Sources/SwiflowRouter/Core/RoutePattern.swift` (decode captures)
- Test: `Tests/SwiflowRouterTests/PathParamDecodingTests.swift` (create)

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/SwiflowRouterTests/PathParamDecodingTests.swift
import Testing
@testable import SwiflowRouter

@Suite("RoutePattern percent-decodes captured path params")
struct PathParamDecodingTests {

    @Test func paramCaptureIsPercentDecoded() {
        let p = RoutePattern("/users/:id")
        #expect(p.match("/users/john%20doe")?["id"] == "john doe")
        #expect(p.match("/users/a%2Fb")?["id"] == "a/b")   // %2F decodes to a literal slash
    }

    @Test func plainParamUnchanged() {
        let p = RoutePattern("/users/:id")
        #expect(p.match("/users/alice")?["id"] == "alice")
    }

    @Test func malformedPercentFallsBackToRaw() {
        // Matches splitQuery's `?? raw` behavior: an invalid %XX leaves the
        // segment as-is rather than dropping the match.
        let p = RoutePattern("/users/:id")
        #expect(p.match("/users/100%")?["id"] == "100%")
    }

    @Test func wildcardCaptureIsPercentDecodedPerSegment() {
        let p = RoutePattern("/files/*")
        // Each segment decoded, then re-joined with literal '/'.
        #expect(p.match("/files/my%20dir/a%20b.txt")?["*"] == "my dir/a b.txt")
    }

    @Test func prefixParamCaptureIsDecoded() {
        let p = RoutePattern("/users/:id")
        let m = p.prefixMatch("/users/john%20doe/posts")
        #expect(m?.params["id"] == "john doe")
        #expect(m?.remainder == "/posts")
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `env -u SWIFLOW_SOURCE swift test --filter PathParamDecodingTests`
Expected: the decoding tests FAIL (`"john%20doe"` etc. stored raw).

- [ ] **Step 3: Extract the shared decoder**

Create `Sources/SwiflowRouter/Core/PercentDecoding.swift` by MOVING the
`percentDecode` and `hexDigit` functions verbatim out of `RouteMatching.swift`,
changing `private` to module-internal (drop the `private` keyword):

```swift
// Sources/SwiflowRouter/Core/PercentDecoding.swift

/// RFC 3986 percent-decoder for URL path segments and query keys/values.
///
/// Returns `nil` for any malformed `%XX` sequence or for byte sequences that do
/// not form valid UTF-8 — matches `String.removingPercentEncoding` semantics,
/// so callers' `?? original` fallback preserves prior behavior on invalid input.
///
/// `+` is left literal (RFC 3986 query semantics; WHATWG URLSearchParams maps
/// `+` to space — a separate choice, tracked by `queryPlusStaysLiteral`).
func percentDecode(_ s: String) -> String? {
    // … move the EXISTING body verbatim from RouteMatching.swift …
}

/// ASCII hex-digit nibble. `nil` for any non-hex byte.
private func hexDigit(_ b: UInt8) -> UInt8? {
    // … move the EXISTING body verbatim …
}
```

In `Sources/SwiflowRouter/Core/RouteMatching.swift`, DELETE the now-moved
`percentDecode` and `hexDigit` definitions. `splitQuery` keeps calling
`percentDecode(...)` unchanged (it now resolves to the shared one).

- [ ] **Step 4: Decode the captures in RoutePattern**

In `Sources/SwiflowRouter/Core/RoutePattern.swift`, decode in BOTH `matchFull`
and `matchPrefix`:

`matchFull` — the `.param` and `.wildcard` cases:
```swift
            case .param(let name):
                guard i < parts.count else { return nil }
                params[name] = percentDecode(parts[i]) ?? parts[i]
                i += 1
            case .wildcard:
                params["*"] = parts[i...].map { percentDecode($0) ?? $0 }.joined(separator: "/")
                i = parts.count
```

`matchPrefix` — the same `.param` and `.wildcard` cases:
```swift
            case .param(let name):
                guard i < parts.count else { return nil }
                params[name] = percentDecode(parts[i]) ?? parts[i]
                i += 1
            case .wildcard:
                params["*"] = parts[i...].map { percentDecode($0) ?? $0 }.joined(separator: "/")
                return (params, [])
```

(Decoding per-segment then joining with a literal `/` is deliberate: a `%2F`
inside one segment decodes to a literal slash in the value without being treated
as a path separator. `matchPrefix`'s `remainder` is built from the still-raw
`parts` via `normalize`/`split`, so the unmatched suffix is unaffected — only
the captured `params` values are decoded. Confirm by reading `prefixMatch`.)

- [ ] **Step 5: Run tests**

Run: `env -u SWIFLOW_SOURCE swift test --filter "PathParamDecodingTests|SwiflowRouter"` → green (existing router tests, incl. query-decoding and `queryPlusStaysLiteral`, must still pass — the decoder moved but is byte-identical).
Run: `env -u SWIFLOW_SOURCE swift test` → full suite green.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "fix(router): percent-decode captured path-segment params

Query params were decoded but path params were stored raw, so
/users/john%20doe yielded params[\"id\"] == \"john%20doe\". The shared
percentDecode (extracted from RouteMatching) now decodes :param and *
captures too. Clears audit MEDIUM: 'path params never percent-decoded
while query params are'."
```

---

### Task 4: CHANGELOG + audit bookkeeping

**Files:**
- Modify: `CHANGELOG.md`, `docs/reviews/2026-06-10-quality-audit.md`

- [ ] **Step 1: CHANGELOG**

Append to the existing `## [Unreleased]` → `### Fixed` list (match formatting):

```markdown
- **Optimistic mutations:** a failed mutation no longer rolls its cache key
  back over a *concurrent* mutation's newer value (or cancels that mutation's
  refetch) — rollback now skips keys that were superseded after the optimistic
  write.
- **`SwiflowFetcher`:** non-finite numbers (`NaN`, `±Infinity`) serialize as
  JSON `null` (matching `JSON.stringify`) instead of the invalid tokens
  `nan`/`inf`.
- **Router:** captured path params are now percent-decoded like query params —
  `/users/john%20doe` yields `params["id"] == "john doe"`.
```

- [ ] **Step 2: Audit annotations**

Append ` **[FIXED — see docs/superpowers/plans/2026-06-10-targeted-mediums.md]**`
to these MEDIUM bullets (search each; report any mismatch):
1. Unit 7: the bullet starting `**Concurrent-mutation rollback can clobber newer state and cancel its repair fetch:**`
2. Unit 5: the bullet starting `**Non-finite doubles produce invalid JSON:**`
3. Unit 8: the bullet starting `**Path params never percent-decoded while query params are:**`

- [ ] **Step 3: Update the Running tally**

Read the tally table. Decrement the MEDIUM column for the affected units:
`SwiflowQuery` Medium −1, `SwiflowFetcher` Medium −1, `SwiflowRouter` Medium −1;
Total Medium 37 → 34. (Report the actual before/after you find.)

- [ ] **Step 4: Final verification + commit**

```bash
env -u SWIFLOW_SOURCE swift test 2>&1 | tail -2   # full suite green
git add CHANGELOG.md docs/reviews/2026-06-10-quality-audit.md
git commit -m "docs: changelog + audit bookkeeping for targeted-mediums round"
```

---

## Verification (end-to-end)

1. `env -u SWIFLOW_SOURCE swift test` — full host suite green (≈810; exact per new tests).
2. `grep -rn "percentDecode" Sources/SwiflowRouter/` — defined once (PercentDecoding.swift), called by both RouteMatching and RoutePattern; no duplicate definition.
3. All three fixes have host-passing regression tests proving the bug is closed.

## Out of scope (deliberately — noted as future candidates, not bugs-with-clean-tests)

- **Router `/a/*/b` (segment after wildcard) silently never matches** — its only
  honest fix is a non-crashing DEBUG warning at construction (hard to test
  cleanly); deferred.
- **`HTTPError.status` discards body / `?? 0` → "HTTP 0"** — the value (debuggable
  failed requests) is real, but the fix lives in JSKit-gated `HTTPClient.send`
  (untestable on host) and grows the public error type; deferred.
- The remaining ~34 Mediums and 42 Lows (encoder duplication, RAFScheduler
  per-frame closure, `valuesEqual` dead plumbing, CLI `ValidationError` misuse,
  comment/naming hygiene) — contained quality issues, not bug-adjacent.
