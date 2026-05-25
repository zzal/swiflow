# Phase 13f — Polish: Atomic Init, `change()` Harness, CHANGELOG

**Date:** 2026-05-25
**Phase:** 13f (Polish — high-value audit minor items)
**Status:** Approved

---

## Goal

Close the three highest-user-value items remaining from the Phase 13 confidence audit's minor list (C4, A5, A6). The remaining seven minor items (R3, R4, E3, E4, C5, C6, A7) are deferred to a later cleanup pass.

## Context

The Phase 13e plan closed all 1 critical + 10 important audit gaps. Ten minor items remain. After scoping, three are high enough leverage to warrant a dedicated phase:

- **C4** (`swiflow init` atomic writes) is a real correctness issue — a failed write currently leaves a half-populated project directory.
- **A5** (`change()` event in `TestHarness`) unlocks unit testing of `<select>` and `<textarea>` forms that use `onChange`. Currently impossible.
- **A6** (CHANGELOG.md with stability signals) is a pre-1.0 stability contract — users today can't tell which APIs may break.

The other seven minor items (R3 router doc gap, R4 conditional-route tests, E3 deep-nesting env tests, E4 `@Environment` in `onAppear`, C5 relative-path help text, C6 expanded `.gitignore`, A7 `fatalError`/`preconditionFailure` uniformity) are real but smaller-impact. They will be closed in a future cleanup phase.

## Architecture

Three independent, single-commit changes, each in its own logical area of the codebase. They share no code paths and can be implemented in any order.

```
C4 → Sources/SwiflowCLI/Project/
A5 → Sources/SwiflowTesting/
A6 → CHANGELOG.md (new top-level)
```

Each ships with its own tests (where applicable) and its own doc update (where applicable).

---

## C4 — Atomic init via write-then-cleanup-on-failure

### Current behaviour

`ProjectWriter.writeProject(name:into:swiflowDep:jsDriverSource:)` creates the target directory, then writes seven files into it (Package.swift, App.swift, index.html, swiflow-driver.js, .gitignore, README.md, and the Sources/App/ subdirectory). The current implementation is fail-fast but not transactional: an error during any single write leaves the target dir partially populated. The user is then blocked from re-running `swiflow init` because the dir exists (the `targetExists` check fires).

### Fix

Wrap the file-write sequence inside `writeProject` in a do/catch. The function already creates the target dir as its first action; if any subsequent file write throws, recursively delete the target dir before re-throwing.

Because `writeProject` rejects pre-existing target dirs up front (`ProjectWriterError.targetExists`), we always own the dir when we reach the write phase. Deleting it on failure is safe — we never delete user data.

### Non-goals

- **True atomicity.** A SIGKILL between the create and the cleanup still leaves partial state. Acceptable per the chosen approach (sibling-temp-dir-and-rename would give true atomicity but adds complexity that's unnecessary for the common failure modes — disk full, permission denied — which both manifest as throws).
- **Rollback in `InitCommand.run()`.** The cleanup lives inside `ProjectWriter` because that's where the dir-creation responsibility lives. Higher-level `InitCommand` failures (e.g., `--path` doesn't exist) happen before any write and need no cleanup.

### Testing

One new test in `Tests/SwiflowCLITests/InitCommandTests.swift` (or a new `ProjectWriterTests.swift` file if `InitCommandTests` is getting crowded):

> "Init cleans up the target directory when a file write fails partway through"

Test setup: pre-create the target dir's `Sources` path as a regular file (not a directory). When `ProjectWriter` later tries to create `Sources/App/` as a directory, `FileManager.createDirectory(at:withIntermediateDirectories:)` will throw. After the throw, assert that the target dir (e.g., `Demo/`) does not exist.

Variant: if blocking via "pre-create as file" is awkward, pre-create the target's parent dir with no write permissions for a subset of operations. Use whichever approach is simpler.

---

## A5 — `change()` event in TestHarness

### Current state

`TestHarness` exposes three event-firing methods, all of which dispatch via `HandlerRegistry`:

- `click(_ tag:text:)` — fires `click`
- `input(_ tag:at:value:)` — fires `input` with `event.target.value`
- `blur(_ tag:at:)` — fires `blur`

A `change()` method is conspicuously missing. The `<select>` and `<textarea>` patterns from Phase 12 (form validation) use `.on(.change) { info in … }`. None of those handlers can be exercised from a unit test today.

### API

Public method on `TestHarness`:

```swift
public func change(_ tag: String = "select", at index: Int = 0, value: String)
```

Behaviour:
- Resolves to the element at `index` among all `tag` matches in document order.
- No-op if `index` is out of range.
- No-op if the element has no `change` handler installed.
- Dispatches `EventInfo(type: "change", targetValue: value)`.
- Flushes the synchronous scheduler before returning.

Internal companion on `TestRenderer`:

```swift
func change(tag: String, at index: Int, value: String)
```

Mirrors `TestRenderer.input(tag:at:value:)` exactly, with the event name `"change"` substituted.

### Testing

Add a new test in `Tests/SwiflowTestingTests/TestHarnessTests.swift`:

> "change() dispatches a change event and updates state via the .on(.change) handler"

Use a file-scope `@MainActor @Component` host that renders `<select>` with `.on(.change) { info in self.selection = info.targetValue ?? "" }`. Render, call `harness.change("select", value: "opt2")`, assert `node.text` reflects the updated state.

### Doc impact

Update `docs/guides/testing.md`:
1. Add `change()` to the "Interactions" section under `blur()`.
2. Remove the bullet under "Limitations" that says "no change event support".

---

## A6 — `CHANGELOG.md` from Phase 7 onward with phase-level stability notes

### Why this matters

Pre-1.0 software changes constantly. The audit's gap statement: "users cannot distinguish 'public and stable' from 'public but may change' before 1.0." A CHANGELOG with explicit per-phase stability annotations gives users a single document to grep for that signal.

### Format

Keep-a-Changelog conventions with one extension: each phase header carries a one-line **Stability** note immediately under the header.

```markdown
# Changelog

All notable user-facing changes to Swiflow.

Swiflow is pre-1.0; APIs can change in any minor phase. Each phase below
carries a Stability note that indicates whether its surface is intended
for current use or is forward-looking infrastructure.

The format is loosely based on Keep a Changelog (https://keepachangelog.com).

## [Phase 13f] — 2026-05-25
**Stability:** Polish only — no API surface changes; closes 3 audit minor items.

### Added
- `TestHarness.change(_:at:value:)` for testing `<select>` and `<textarea>` `onChange` handlers.
- `CHANGELOG.md` with retroactive entries from Phase 7.

### Fixed
- `swiflow init` cleans up the target directory when a file write fails partway through.

## [Phase 13e] — 2026-05-25
**Stability:** Stable for pre-1.0 usage. The `--swiflow-version` flag is forward-looking — the placeholder URL has no live release yet.

### Added
- `.environment()` postfix VNode modifier.
- `--swiflow-version <version>` flag + `SwiflowDep` enum for URL-based generated `Package.swift`.
- `examples/RouterDemo` + `Tests/playwright/router.spec.ts` hash-mode router e2e test.
- `docs/guides/testing.md` SwiflowTesting user guide.

### Changed
- `TestNode.properties` now returns `[String: String]` (was `[String: PropertyValue]`).
- `EnvironmentValues` conforms to `Equatable`; `VNode` diff detects environment changes correctly.

### Fixed
- WASM cross-compile regression from Phase 13d: `@Component` classes require explicit `@MainActor`.
- Dev driver RAF shim guarded for environments without `requestAnimationFrame` (jsdom).

### Breaking
- `Patch`, `PatchPayload`, `PatchSerializer`, `HandleAllocator`, `MountNode` demoted from `public` to `package` access.
- `Templates.packageSwift` and `ProjectWriter.writeProject` signatures: `swiflowSource: String` → `swiflowDep: SwiflowDep`.

... (full retroactive entries for each phase that shipped between 7 and 13d follow the same shape — each with its own Stability note and Added/Changed/Fixed/Breaking sections as appropriate; the implementer should consult `git log` + README + `docs/superpowers/` to enumerate the actual phase headers — not every numbered phase shipped, and some sub-phases like 12a/12b/13a/13b/13c/13d each get their own entry)
```

### Stability vocabulary

Three canonical phrases — pick one per phase header:

- **"Stable for pre-1.0 usage"** — the phase's API surface is intended for current use; breaking changes will be called out in future phases.
- **"Experimental — interface may change"** — the phase introduced something that's intentionally subject to redesign (e.g., AsyncTestRenderer when it lands).
- **"Forward-looking infrastructure — not yet live"** — the code is in the tree but doesn't function end-to-end (e.g., the placeholder Swiflow release URL).

### Scope

Retroactive entries from **Phase 7 (Bindings, Refs & Form Foundations)** through Phase 13e. Going further back is revisionist — Phase 1–6 were API churn before the public surface stabilised.

For each phase, gather material from:
- The phase's `docs/superpowers/specs/` design document (if present).
- The phase's `docs/superpowers/plans/` implementation plan (if present).
- The corresponding `git log` range, scanning commit subjects for user-visible changes.
- The README's phase status notes.

Don't enumerate every commit — group by user-facing feature. The audience is a user reading the file to learn what changed, not a maintainer reading commit-level archaeology.

### Non-goals

- **Per-entry stability tags** (e.g., `[stable]` on individual bullets). Rejected — adds noise; the phase-level note covers 95% of the value.
- **Per-symbol `@stable` doc comments.** Deferred to the master plan's 1.0 API surface audit, which can scan the full public surface and add `@available(*, introduced: 1.0)` systematically.
- **Automated CHANGELOG generation** from commits or conventional-commit prefixes. Manual curation gives better user-facing prose for pre-1.0 work; can revisit post-1.0.

### Verification

No automated test. Manual review against:
- `git log --oneline` for each phase's commit range.
- The README's phase status line.
- Each phase's spec/plan in `docs/superpowers/`.

---

## File Structure

**Modify:**
- `Sources/SwiflowCLI/Project/ProjectWriter.swift` — add write-then-cleanup-on-failure wrapper.
- `Sources/SwiflowTesting/TestHarness.swift` — add `change(_:at:value:)` public method.
- `Sources/SwiflowTesting/TestRenderer.swift` — add internal `change(tag:at:value:)` dispatcher.
- `Tests/SwiflowCLITests/InitCommandTests.swift` — add cleanup-on-failure test.
- `Tests/SwiflowTestingTests/TestHarnessTests.swift` — add `change()` test + `<select>` host component.
- `docs/guides/testing.md` — document `change()`; remove the "no change event support" limitation.

**Create:**
- `CHANGELOG.md` — top-level, Phase 7 → 13f entries.

## Commit Boundary

Three commits, in any order:

1. `fix(init): clean up target directory on partial-write failure` (C4)
2. `feat(testing): add TestHarness.change() for select/textarea onChange` (A5)
3. `docs: seed CHANGELOG.md with Phase 7 → 13f retroactive entries` (A6)

## Out of Scope

- The seven other audit minor items (R3, R4, E3, E4, C5, C6, A7).
- The master plan's outstanding Phase 13 work (bundle-size CI, lazy components, 1.0 API surface audit, migration guides).
- Per-symbol stability annotations in source code.
