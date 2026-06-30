# Fix #96 — `.noValue` optimistic edit skips silently — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `MutationRuntime.beginOptimistic`'s `.noValue` case a silent skip instead of a DEBUG trap, so optimistically mutating a not-yet-loaded query no-ops rather than crashing.

**Architecture:** One-line production change (drop a `swiflowDiagnostic` call) + one regression test reusing the existing query fuzz harness. Test-first.

**Tech Stack:** Swift 6.3, swift-testing. Host (`swift test`).

**Spec:** `docs/superpowers/specs/2026-06-30-optimistic-novalue-silent-skip-design.md`.

**Critical context:**
- The buggy code is in `Sources/SwiflowQuery/MutationState.swift`, `beginOptimistic`, lines 68–71:
  ```swift
  case .noValue:
      #if DEBUG
      swiflowDiagnostic("OptimisticEdit.update: no cached value for key \(edit.key) — edit skipped.")
      #endif
  ```
  `swiflowDiagnostic` (`Sources/Swiflow/Reactivity/Diagnostics.swift`) is a `preconditionFailure` in DEBUG unless `_swiflowDiagnosticOverride` is set.
- The regression test reuses the existing harness in `Tests/SwiflowQueryTests/QueryStateMachineFuzzTests.swift`: `FuzzWorld` (with `model`, `mutate(_:_:)`, `settle()`), the private `AppendMut` mutation, and `ServerModel.value(_:)`. `_swiflowDiagnosticOverride` and `Issue`/`#expect` are available (`import Swiflow`, `import Testing`).
- No test pins the trap (`MutationCoreTypesTests.updateReportsNoValueWhenAbsent` tests `OptimisticEdit.apply(nil)`'s `.noValue` outcome, not the runtime reaction) — leave it untouched.

**Branch:** `fix/optimistic-novalue-silent-skip` (created off `origin/main`; spec committed there).

---

## Task 1: Silent `.noValue` skip + regression test

**Files:**
- Modify: `Sources/SwiflowQuery/MutationState.swift` (`beginOptimistic`, the `.noValue` case)
- Test: `Tests/SwiflowQueryTests/QueryStateMachineFuzzTests.swift` (append one test)

- [ ] **Step 1: Write the failing test.** Append inside `struct QueryStateMachineFuzzTests` in `Tests/SwiflowQueryTests/QueryStateMachineFuzzTests.swift`:

```swift
    @Test("optimistic edit on an unsubscribed query skips silently (no trap, no diagnostic)")
    func optimisticNoValueSkipsSilently() async {
        var captured: [String] = []
        let prior = _swiflowDiagnosticOverride
        _swiflowDiagnosticOverride = { captured.append($0) }
        defer { _swiflowDiagnosticOverride = prior }

        let w = FuzzWorld()
        // id 7 is never subscribed → its query holds no cached value → .noValue.
        w.mutate(AppendMut(id: 7, model: w.model), 42)
        await w.settle()

        // Silent skip: no "no cached value" diagnostic is emitted (before the fix,
        // this string was passed to swiflowDiagnostic, which traps in DEBUG).
        #expect(!captured.contains { $0.contains("no cached value") })
        // The mutation's perform still ran and reconciled the server truth.
        #expect(w.model.value(7) == [42])
    }
```

- [ ] **Step 2: Run the test to verify it fails.**

Run: `swift test --filter optimisticNoValueSkipsSilently`
Expected: FAIL — `captured` contains the `"…no cached value…"` message (the override captured the diagnostic the current code emits), so `#expect(!captured.contains { … })` fails.

- [ ] **Step 3: Apply the fix.** In `Sources/SwiflowQuery/MutationState.swift`, replace the `.noValue` case (lines 68–71):

```swift
                case .noValue:
                    #if DEBUG
                    swiflowDiagnostic("OptimisticEdit.update: no cached value for key \(edit.key) — edit skipped.")
                    #endif
```

with:

```swift
                case .noValue:
                    // The query isn't loaded yet — there is nothing to optimistically
                    // transform. Skip this optimistic layer silently (per
                    // OptimisticEdit's .noValue contract: "skipped silently"); the
                    // mutation's perform() and the post-success invalidation/refetch
                    // reconcile the cache. (Previously this trapped via swiflowDiagnostic.)
                    break
```

Leave the `.typeMismatch` and the no-client `else` branches exactly as they are.

- [ ] **Step 4: Run the test to verify it passes.**

Run: `swift test --filter optimisticNoValueSkipsSilently`
Expected: PASS.

- [ ] **Step 5: Confirm `.typeMismatch` is unchanged and the suite is green.**

Run: `swift test`
Expected: PASS — full host suite green, including `MutationCoreTypesTests` (the `.noValue` *outcome* test still passes; it never exercised the runtime trap) and all `QueryStateMachineFuzzTests`.

- [ ] **Step 6: Commit.**

```bash
git add Sources/SwiflowQuery/MutationState.swift Tests/SwiflowQueryTests/QueryStateMachineFuzzTests.swift
git commit -m "fix(query): optimistic edit on an unloaded query skips silently, not trap (#96)

beginOptimistic's .noValue routed through swiflowDiagnostic (preconditionFailure
in DEBUG), crashing 'optimistic mutate before the query loads' — contrary to
OptimisticEdit's documented benign silent-skip intent. Drop the diagnostic;
.typeMismatch still traps (genuine programmer error).

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Final verification

- [ ] `swift test` green.
- [ ] Open a PR from `fix/optimistic-novalue-silent-skip` → `main` referencing #96 (`Closes #96`). **Do not merge** until the user says "merge it -- CI is green" (`gh pr merge <n> --admin --rebase`).

## Spec coverage check

- `.noValue` no longer traps; `perform` still runs → Task 1 Steps 3–4.
- `.typeMismatch` still traps (unchanged) → Task 1 Step 3 (left as-is) + Step 5.
- Suite green incl. `MutationCoreTypesTests` → Task 1 Step 5.
