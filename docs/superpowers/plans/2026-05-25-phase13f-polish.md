# Phase 13f — Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the 3 highest-user-value items from the Phase 13 confidence audit's minor list: C4 (atomic init writes), A5 (`change()` in TestHarness), A6 (CHANGELOG.md).

**Architecture:** Three independent commits, each in its own area of the codebase: `Sources/SwiflowCLI/Project/` for C4, `Sources/SwiflowTesting/` for A5, and a new top-level `CHANGELOG.md` for A6. No shared code paths. Each task is implementable in any order.

**Tech Stack:** Swift 6, Swift Testing, Foundation `FileManager`, Markdown (Keep-a-Changelog).

---

## File Structure

**Create:**
- `CHANGELOG.md` — top-level, retroactive entries from Phase 7 → 13f

**Modify:**
- `Sources/SwiflowCLI/Project/ProjectWriter.swift` — wrap writes in do/catch with cleanup; add test-only `_testFailDuringWrites` parameter
- `Sources/SwiflowTesting/TestHarness.swift` — public `change(_:at:value:)`
- `Sources/SwiflowTesting/TestRenderer.swift` — internal `change(tag:at:value:)`
- `Tests/SwiflowCLITests/InitCommandTests.swift` — cleanup-on-failure test
- `Tests/SwiflowTestingTests/TestHarnessTests.swift` — `change()` test + `<select>` host component
- `docs/guides/testing.md` — document `change()`; remove the "no change event support" limitation

---

## Task 1: C4 — Atomic init via write-then-cleanup-on-failure

**Files:**
- Modify: `Sources/SwiflowCLI/Project/ProjectWriter.swift`
- Test: `Tests/SwiflowCLITests/InitCommandTests.swift`

`ProjectWriter.writeProject` currently writes seven files into a freshly-created target directory. If any single write throws, the directory is left half-populated and the user is blocked from re-running `swiflow init` (the `targetExists` check fires on the next attempt). Fix: wrap the file-write block in a do/catch and recursively delete the target dir on any failure, then re-throw the original error.

We also add a test-only `_testFailDuringWrites: Bool = false` parameter that lets us deterministically simulate a write failure. The leading underscore signals "test infrastructure"; production callers omit the parameter.

- [ ] **Step 1: Read the current implementation**

Read `Sources/SwiflowCLI/Project/ProjectWriter.swift` (the whole file — it's ~70 lines). Note the exact ordering: `createDirectory` first, then six `.write(to:)` calls.

- [ ] **Step 2: Write the failing test**

Add to `Tests/SwiflowCLITests/InitCommandTests.swift`, inside the existing `@Suite("InitCommand")` struct (just after `refusesOverwrite`):

```swift
@Test("Init cleans up the target directory when a file write fails partway through")
func cleansUpOnFailure() throws {
    let tmp = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: tmp) }

    // Force a failure between createDirectory and the file writes.
    #expect(throws: ProjectWriterError.self) {
        try ProjectWriter.writeProject(
            name: "Demo",
            into: tmp,
            swiflowDep: .path("/abs/path/to/swiflow"),
            jsDriverSource: "// driver\n",
            _testFailDuringWrites: true
        )
    }

    // The target must not exist after the failure.
    let project = tmp.appendingPathComponent("Demo")
    #expect(!FileManager.default.fileExists(atPath: project.path),
            "ProjectWriter must remove the target directory when writes fail; found leftover at \(project.path)")
}
```

- [ ] **Step 3: Run the test to verify it fails**

```bash
swift test --filter "cleansUpOnFailure" 2>&1 | tail -10
```

Expected: Compilation FAIL — `extra argument '_testFailDuringWrites' in call` (the parameter doesn't exist yet).

- [ ] **Step 4: Add the cleanup and test hook to `ProjectWriter.writeProject`**

Replace the body of `ProjectWriter.writeProject` in `Sources/SwiflowCLI/Project/ProjectWriter.swift`:

```swift
static func writeProject(
    name: String,
    into parent: URL,
    swiflowDep: SwiflowDep,
    jsDriverSource: String,
    _testFailDuringWrites: Bool = false
) throws {
    let fm = FileManager.default
    // Use `isDirectory: false` so the URL we construct (and surface in
    // errors) doesn't sprout a trailing slash if the path already exists
    // on disk as a directory — keeping it equal to the URL a caller would
    // pre-compute via the same plain `appendingPathComponent(name)` call.
    let project = parent.appendingPathComponent(name, isDirectory: false)

    if fm.fileExists(atPath: project.path) {
        throw ProjectWriterError.targetExists(project)
    }

    // Create the directory tree.
    try fm.createDirectory(
        at: project.appendingPathComponent("Sources/App"),
        withIntermediateDirectories: true
    )

    // Write files. Any error during this phase triggers cleanup of the
    // half-populated target dir so the user can re-run `swiflow init`
    // without first manually removing the partial output.
    do {
        if _testFailDuringWrites {
            // Use targetExists with the same URL so tests can pattern-match
            // on ProjectWriterError without inventing a new case.
            throw ProjectWriterError.targetExists(project)
        }
        try Templates.packageSwift(name: name, swiflowDep: swiflowDep)
            .write(to: project.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try Templates.appSwift(name: name)
            .write(to: project.appendingPathComponent("Sources/App/App.swift"), atomically: true, encoding: .utf8)
        try Templates.indexHTML(name: name)
            .write(to: project.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        try Templates.gitignore()
            .write(to: project.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        try Templates.readme(name: name)
            .write(to: project.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try jsDriverSource
            .write(to: project.appendingPathComponent("swiflow-driver.js"), atomically: true, encoding: .utf8)
    } catch {
        // Best-effort cleanup; ignore removal errors so we still surface
        // the original failure to the caller.
        try? fm.removeItem(at: project)
        throw error
    }
}
```

Also update the function's docstring (the one between the `enum ProjectWriter {` line and the function signature) to mention the cleanup semantic. Append to the existing docstring's `- Throws:` line:

```swift
    /// - Throws: `ProjectWriterError.targetExists` if `<into>/<name>/` already exists, or
    ///   any `FileManager` error encountered while creating directories / writing files.
    ///   If a write fails after the target dir is created, the target dir is removed
    ///   before the error is re-thrown — the user can re-run `swiflow init` without
    ///   first manually deleting the partial output.
```

- [ ] **Step 5: Run the test to verify it passes**

```bash
swift test --filter "cleansUpOnFailure" 2>&1 | tail -5
```

Expected: PASS.

- [ ] **Step 6: Run the full SwiflowCLI test suite to confirm no regression**

```bash
swift test --filter "SwiflowCLITests" 2>&1 | tail -5
```

Expected: All previously-passing CLI tests still pass. The pre-existing WASM-gated tests pass (they ran successfully in the last full session run).

- [ ] **Step 7: Commit**

```bash
git add Sources/SwiflowCLI/Project/ProjectWriter.swift Tests/SwiflowCLITests/InitCommandTests.swift
git commit -m "fix(init): clean up target directory on partial-write failure

When ProjectWriter.writeProject failed after the target directory was
created but before all files were written, the half-populated directory
was left on disk. Users then hit ProjectWriterError.targetExists on the
next attempt and had to clean up by hand.

Wrap the write block in a do/catch. On any thrown error, recursively
remove the target directory before re-throwing the original error.
Adds a test-only _testFailDuringWrites parameter to make the failure
path deterministically testable.

Closes audit gap C4."
```

---

## Task 2: A5 — `change()` event in TestHarness

**Files:**
- Modify: `Sources/SwiflowTesting/TestHarness.swift`
- Modify: `Sources/SwiflowTesting/TestRenderer.swift`
- Modify: `docs/guides/testing.md`
- Test: `Tests/SwiflowTestingTests/TestHarnessTests.swift`

`TestHarness` exposes `click()`, `input()`, `blur()` but no `change()`. Forms using `<select>` or `<textarea>` with `.on(.change)` handlers cannot currently be tested. This task mirrors the existing `input()` pattern exactly, substituting the event name `"change"`.

- [ ] **Step 1: Verify the DSL has `select`, `option`, and `Event.change`**

Read `Sources/Swiflow/DSL/Elements.swift` to confirm `select(...)` and `option(...)` exist (Phase 12 forms used them, so they likely do). Read `Sources/Swiflow/DSL/Event.swift` to confirm `.change` is a case in the `Event` enum.

If `.change` is missing, you'll add it in Step 3. If the element builders are missing, you'll need to construct VNodes manually — but Phase 12b forms used `<select>`/`<textarea>` with `.selection($choice)` two-way binding, so the builders almost certainly exist.

- [ ] **Step 2: Write the failing test**

Add a file-scope test component to `Tests/SwiflowTestingTests/TestHarnessTests.swift` (place it next to the other helper components like `PropHost`):

```swift
@MainActor @Component
private final class SelectHost {
    @State var selection = "opt1"

    var body: VNode {
        div {
            select(.on(.change) { info in self.selection = info.targetValue ?? self.selection }) {
                option(.attr("value", "opt1")) { text("Option 1") }
                option(.attr("value", "opt2")) { text("Option 2") }
            }
            p("Selected: \(selection)")
        }
    }
}
```

Then add the test inside an existing `@Suite("...")` struct in the same file (a suite that's already `@MainActor`, or wrap the test method itself in `@MainActor`):

```swift
@Test("change() dispatches a change event and updates state via the .on(.change) handler")
@MainActor
func changeUpdatesStateViaOnChangeHandler() {
    let h = render(SelectHost())
    #expect(h.find("p")?.text == "Selected: opt1")
    h.change("select", value: "opt2")
    #expect(h.find("p")?.text == "Selected: opt2")
}
```

- [ ] **Step 3: Run the test to verify it fails**

```bash
swift test --filter "changeUpdatesStateViaOnChangeHandler" 2>&1 | tail -10
```

Expected: Compilation FAIL — `value of type 'TestHarness' has no member 'change'`. (If `Event.change` is also missing, you'll see a second failure about that — that's expected and fixed in the next step.)

- [ ] **Step 4: If needed, add `.change` to the Event enum**

Read `Sources/Swiflow/DSL/Event.swift`. If `Event` is an enum like:

```swift
public enum Event { case click; case input; case blur; ... }
```

and `change` is missing, add it:

```swift
public enum Event {
    case click
    case input
    case blur
    case change  // ← add this case alongside existing cases
    // ... other cases
}
```

Plus wherever the event name string mapping lives (look for `case .click: return "click"` style code in the same file or nearby), add the mapping for `.change` → `"change"`.

If `change` is already present, skip this step.

- [ ] **Step 5: Add the internal dispatcher to TestRenderer**

In `Sources/SwiflowTesting/TestRenderer.swift`, add a new method right after the existing `blur(tag:at:)` method. Mirror the structure of `input(tag:at:value:)`:

```swift
func change(tag: String, at index: Int, value: String) {
    let matches = findElements(tag: tag, text: nil, in: mountTree)
    guard index < matches.count else { return }
    let (node, _) = matches[index]
    guard let id = node.handlerIds["change"] else { return }
    handlers.dispatch(id: id, event: EventInfo(type: "change", targetValue: value))
    scheduler.flush()
}
```

- [ ] **Step 6: Add the public method to TestHarness**

In `Sources/SwiflowTesting/TestHarness.swift`, add a new method right after the existing `blur(_:at:)` method:

```swift
/// Fires a `change` event on the element at position `index` among all
/// elements matching `tag` (default `"select"`) and flushes. No-op if
/// out-of-bounds or if the element has no `change` handler.
///
/// Use for `<select>` and `<textarea>` with `.on(.change)` handlers;
/// pair with `.input(...)` for `<input>` elements that use `.on(.input)`.
public func change(_ tag: String = "select", at index: Int = 0, value: String) {
    renderer.change(tag: tag, at: index, value: value)
}
```

- [ ] **Step 7: Run the test to verify it passes**

```bash
swift test --filter "changeUpdatesStateViaOnChangeHandler" 2>&1 | tail -5
```

Expected: PASS.

- [ ] **Step 8: Update `docs/guides/testing.md` — add `change()` documentation**

In `docs/guides/testing.md`, find the `### \`blur(_ tag: at:)\`` section. Just after the closing of the blur section (right before `## Recipes`), add a new subsection:

```markdown
### `change(_ tag: at: value:)`

Fires a `change` event on the element at `index` among all elements matching
`tag` (default `"select"`) and flushes. Use for `<select>` and `<textarea>`
elements with `.on(.change)` handlers.

```swift
h.change("select", value: "opt2")

// tag defaults to "select", at defaults to 0:
h.change(value: "opt2")
```

The event's `targetValue` is set to the provided `value` string. No-op if
out-of-bounds or the element has no `change` handler. For `<input>` elements
that use `.on(.input)`, use `input(...)` instead.
```

- [ ] **Step 9: Update `docs/guides/testing.md` — remove the limitation note**

In `docs/guides/testing.md`, find the `## Limitations` section. Remove this bullet:

```markdown
- **No `change` event support.** `<select>` and `<textarea>` `onChange`
  handlers cannot currently be dispatched. Use `input` as a workaround where
```

If the bullet runs onto a continuation line ("the host element accepts it" or similar), remove that too. Keep the other limitation bullets (async/await, keyboard/mouse-position events) intact.

- [ ] **Step 10: Run the full SwiflowTesting test suite + the docs guide test (if any)**

```bash
swift test --filter "SwiflowTestingTests" 2>&1 | tail -5
swift build 2>&1 | tail -3
```

Expected: All tests pass; build clean. The new `changeUpdatesStateViaOnChangeHandler` test passes alongside the existing ones.

- [ ] **Step 11: Commit**

```bash
git add Sources/SwiflowTesting/TestHarness.swift Sources/SwiflowTesting/TestRenderer.swift Tests/SwiflowTestingTests/TestHarnessTests.swift docs/guides/testing.md
# If you also modified Sources/Swiflow/DSL/Event.swift in Step 4:
git add Sources/Swiflow/DSL/Event.swift

git commit -m "feat(testing): add TestHarness.change() for select/textarea onChange

TestHarness exposed click(), input(), and blur() but no change(),
making it impossible to unit-test <select> and <textarea> elements
with .on(.change) handlers (used by Phase 12 form patterns).

Mirrors the existing input() shape exactly: change(_ tag = \"select\",
at: index = 0, value:) dispatches a change event with the supplied
targetValue and flushes synchronously.

Updates docs/guides/testing.md to document the new method and removes
the corresponding limitation note.

Closes audit gap A5."
```

---

## Task 3: A6 — `CHANGELOG.md` from Phase 7 onward

**Files:**
- Create: `CHANGELOG.md`

Write a top-level `CHANGELOG.md` retroactively documenting each phase from 7 (Bindings, Refs & Form Foundations) through 13f, in Keep-a-Changelog format with a phase-level Stability note.

This task is research-heavy. There's no automated test — verification is manual review against `git log`, the README phase status, and `docs/superpowers/`.

- [ ] **Step 1: Enumerate the phases that actually shipped**

Run the following commands to gather raw material:

```bash
# Phase doc enumeration
ls docs/superpowers/specs/ | sort
ls docs/superpowers/plans/ | sort

# Status line in README — has the canonical phase narrative
grep -A 5 "Phase 13" README.md | head -30

# Full commit history grouped by likely phase boundaries
git -C . log --oneline --no-merges | head -80
```

From this, list every phase that has a spec OR a plan OR a clear feat/fix grouping in the commit log between Phase 7 and Phase 13f. Expected (verify against the actual repo):

- Phase 7 — Bindings, Refs & Form Foundations
- Phase 8 — HMR (state-preserving WASM hot swap)
- Phase 11 — SwiflowRouter
- Phase 12a — CSS-in-Swift, scoped styles, exit animations
- Phase 12b — Form Validation
- Phase 13a — SwiflowTesting (headless test harness)
- Phase 13b — Browser Debugging (DWARF, error overlays)
- Phase 13c — Multi-Root & Unmount
- Phase 13d — Macro Diagnostics & `@Component`
- Phase 13e — Confidence Fixes (audit)
- Phase 13f — Polish (this phase)

If Phase 9 or Phase 10 produced shippable code, include them. If they were planned-but-not-shipped (per the master plan), omit them from the CHANGELOG — that's a status, not a release.

- [ ] **Step 2: Gather user-facing changes for each phase**

For each phase identified in Step 1, run:

```bash
# Find the relevant spec/plan
ls docs/superpowers/specs/ | grep -i "phase-?<N>"   # adjust per phase
ls docs/superpowers/plans/ | grep -i "phase-?<N>"

# Get the commit range. The spec or plan commit usually anchors the phase.
# Use `git log --oneline <start-sha>..<end-sha>` to enumerate within the range.
# OR — use the commits that touched files matching the phase's scope.
git log --oneline -- Sources/Swiflow/Reactivity/State.swift   # Phase 7 binding work
```

For each phase, collect:
- 1–4 bullet points of user-visible Added features
- Notable Changed / Fixed / Breaking items if any
- A one-line Stability assessment

Use Phase 13e and 13f as your gold-standard format (you wrote 13e's bullets above; 13f's are below). Don't enumerate every commit — group commits into user-visible features.

- [ ] **Step 3: Write `CHANGELOG.md`**

Create `./CHANGELOG.md`. Start with this exact header:

```markdown
# Changelog

All notable user-facing changes to Swiflow.

Swiflow is pre-1.0; APIs can change in any minor phase. Each phase below
carries a **Stability** note that indicates whether its surface is intended
for current use or is forward-looking infrastructure:

- **Stable for pre-1.0 usage** — intended for current use; breaking changes
  are flagged explicitly in later phases.
- **Experimental — interface may change** — intentionally subject to redesign.
- **Forward-looking infrastructure — not yet live** — in tree but not yet
  functional end-to-end.

The format is loosely based on [Keep a Changelog](https://keepachangelog.com).
```

Then write Phase 13f's entry first (this phase, ship-time TBD — use today's date `2026-05-25`):

```markdown
## [Phase 13f] — 2026-05-25
**Stability:** Polish only — no API surface changes; closes 3 audit minor items.

### Added
- `TestHarness.change(_:at:value:)` for testing `<select>` and `<textarea>` `onChange` handlers (closes A5).
- `CHANGELOG.md` with retroactive entries from Phase 7 (closes A6).

### Fixed
- `swiflow init` cleans up the target directory when a file write fails partway through (closes C4).
```

Then write Phase 13e's entry:

```markdown
## [Phase 13e] — 2026-05-25
**Stability:** Stable for pre-1.0 usage. `--swiflow-version` is forward-looking — its placeholder URL has no live release yet.

### Added
- `.environment(_:_:)` postfix VNode modifier (alongside existing `withEnvironment`).
- `--swiflow-version <version>` flag and `SwiflowDep` enum for URL-based generated `Package.swift`.
- `examples/RouterDemo` + `Tests/playwright/router.spec.ts` hash-mode router end-to-end test.
- `docs/guides/testing.md` user guide for `SwiflowTesting`.
- Verified `@Environment(\.router)` propagation across `embed {}` boundaries.

### Changed
- `TestNode.properties` now returns `[String: String]` (was `[String: PropertyValue]`).
- `EnvironmentValues` conforms to `Equatable` via type-erased equality; `VNode` diff now detects environment changes correctly (was silently skipping subtrees on env-only differences).

### Fixed
- WASM cross-compile regression from Phase 13d: `@Component` classes now require explicit `@MainActor` (canonical pattern: `@MainActor @Component final class Foo`). Swift 6 doesn't propagate isolation retroactively through macro-emitted conformance extensions.
- Dev driver RAF shim guarded for environments without `requestAnimationFrame` (fixed JS driver tests under jsdom).

### Breaking
- `Patch`, `PatchPayload`, `PatchSerializer`, `HandleAllocator`, `MountNode` demoted from `public` to `package` access. No external code should have been using these.
- `Templates.packageSwift` and `ProjectWriter.writeProject` signatures: `swiflowSource: String` → `swiflowDep: SwiflowDep`.
```

Continue with entries for Phase 13d, 13c, 13b, 13a, 12b, 12a, 11, 8, 7 in **reverse chronological order** (most recent first — Keep-a-Changelog convention). Use the same shape: `## [Phase X] — YYYY-MM-DD` header, **Stability** line, then `### Added` / `### Changed` / `### Fixed` / `### Breaking` subsections as applicable. Omit sections that have no entries for that phase (don't write empty `### Breaking`).

For each phase, source the date from the latest commit in that phase's range (use `git log --format=%ad --date=short -1 <commit>`).

Phase 13d guidance: include the `@Component` macro and `@ChildrenBuilder` diagnostics + `text(_:)` free functions. Note the Phase 13e correction in the entry (e.g., under Stability: "Stable for pre-1.0 usage. The `@Component` macro requires explicit `@MainActor` — see Phase 13e for the correction.").

Phase 13c guidance: multi-root render, `Swiflow.unmount(into:)`, lifted the single-root precondition.

Phase 13b guidance: DWARF debugging symbols, full-viewport dev error overlay, Chrome DevTools debugging guide (`docs/guides/debugging.md`).

Phase 13a guidance: `SwiflowTesting` module, `render(_:)`, `TestHarness`, `TestNode`, `find/findAll/click/input/blur`.

Phase 12b guidance: `FormController`, `Field`, `Form` coordinator, `.required()`, `.email`, `.minLength`, `.custom`, blur-triggered errors, `touchAll()`, `reset()`, `isValid`.

Phase 12a guidance: `css { }` builder, `rule()`, `keyframes()`, `from {}` / `to {}` / `at(_:)`, ~50 CSS property functions, `static var scopedStyles: CSSSheet?`, `static var exitAnimation: String?` + `exitDuration`.

Phase 11 guidance: `SwiflowRouter`, `RouterRoot`, `Route`, `RouteBuilder`, `Link`, `Router` value, `@Environment(\.router)`, hash & history modes.

Phase 8 guidance: state-preserving WASM hot swap on save, JS driver logs `[swiflow] hmr-swap took Xms`, `@State` survival across saves.

Phase 7 guidance: `@State` property wrapper with Mirror-based wiring + `RAFScheduler`, two-way bindings `.value($)`, `.checked($)`, `.selection($)`, `Ref<Element>`, `onAppear` / `onChange` / `onDisappear` lifecycle hooks, the typed `Event` enum.

- [ ] **Step 4: Spot-verify against the README and git log**

Pick three phases at random and cross-check the bullets you wrote:

```bash
# For each chosen phase, e.g. Phase 11:
grep -A 3 "Phase 11" README.md
git log --oneline | grep -iE "router|route|link" | head -20
ls docs/superpowers/specs/ | grep -i "phase-?11\|router"
```

Confirm the bullets accurately reflect what shipped (no inventing features; no omitting major ones). If a phase's bullets feel thin or wrong, re-read the spec/plan for that phase.

- [ ] **Step 5: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: seed CHANGELOG.md with Phase 7 → 13f retroactive entries

Keep-a-Changelog format with one entry per shipped phase from 7 to 13f.
Each phase header carries a one-line Stability note (Stable for pre-1.0
usage / Experimental / Forward-looking infrastructure) so users have a
single document to grep for the stable-vs-may-change signal that the
audit's A6 called out.

Phases 1–6 are deliberately omitted as pre-public-API churn.

Closes audit gap A6."
```

---

## Post-implementation verification

After all three commits:

- [ ] **Run the full test suite**

```bash
swift test 2>&1 | tail -5
```

Expected: 526 tests pass (524 from Phase 13e + 1 from Task 1 + 1 from Task 2). 0 failures. WASM E2E tests still pass.

- [ ] **Run JS driver tests**

```bash
cd js-driver && npm test
cd ..
```

Expected: 15 tests pass. No change from Phase 13e baseline.

- [ ] **Audit gap closure summary**

Confirm each item closed:

| ID | Task | Verification |
|----|------|--------------|
| C4 | Task 1 | `swift test --filter cleansUpOnFailure` passes |
| A5 | Task 2 | `swift test --filter changeUpdatesStateViaOnChangeHandler` passes; `docs/guides/testing.md` has `change()` section |
| A6 | Task 3 | `CHANGELOG.md` exists with entries from Phase 7 → 13f; each entry has a Stability note |

Seven audit minor items remain deferred (R3, R4, E3, E4, C5, C6, A7) — to be closed in a future cleanup phase.
