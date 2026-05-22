# Phase 13.0 — `swiflow init` outside-repo fix

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `swiflow init` fail fast with a helpful error when `--swiflow-source` is omitted, rather than silently generating a broken project.

**Architecture:** Change `swiflowSource` from `String = "../.."` to `String?`, add an ArgumentParser `validate()` hook that throws a `ValidationError` with an actionable message, and update the two unit tests that assumed the old default.

**Tech Stack:** Swift, swift-argument-parser (`ArgumentParser`), Swift Testing (`@Suite`, `@Test`, `#expect`).

---

## File map

| File | Change |
|---|---|
| `Sources/SwiflowCLI/Commands/InitCommand.swift` | Remove default; add `validate()`; update help text; force-unwrap in `run()` |
| `Tests/SwiflowCLITests/InitCommandTests.swift` | Split "Defaults" test; add `missingSwiflowSource`; fix `refusesMissingPath` |

No other files change. `ProjectWriter`, `Templates`, and the E2E tests (`DevCommandTests`, `BuildCommandTests`) already pass `swiflowSource` as an explicit concrete value and are unaffected.

---

### Task 1: Update tests (TDD — write the failure first)

**Files:**
- Modify: `Tests/SwiflowCLITests/InitCommandTests.swift`

- [ ] **Step 1: Open `Tests/SwiflowCLITests/InitCommandTests.swift` and locate `@Suite("InitCommand argv")`**

  It starts at line 130. The suite contains three `@Test` functions. You will touch two of them and add one.

- [ ] **Step 2: Replace the `defaults()` test with two focused tests**

  Delete the existing `@Test("Defaults: --path is .")` function (lines 133–139) and replace it with:

  ```swift
  @Test("Default: --path is .")
  func defaultPath() throws {
      let parsed = try InitCommand.parse(["demo", "--swiflow-source", "/some/path"])
      #expect(parsed.name == "demo")
      #expect(parsed.path == ".")
  }

  @Test("Missing --swiflow-source surfaces a ValidationError")
  func missingSwiflowSource() {
      #expect(throws: ValidationError.self) {
          try InitCommand.parse(["demo"])
      }
  }
  ```

  The `defaultPath` test no longer checks `swiflowSource == "../.."` — that assertion belonged to the old default and is now gone.

- [ ] **Step 3: Fix `refusesMissingPath` in `@Suite("InitCommand run()")`**

  Locate `@Test("--path that doesn't exist surfaces a ValidationError")` (around line 182). It currently parses without `--swiflow-source`. After the change, the missing-source `validate()` will fire before `run()` checks the path, so the test would pass for the wrong reason. Add `--swiflow-source`:

  ```swift
  @Test("--path that doesn't exist surfaces a ValidationError")
  func refusesMissingPath() async throws {
      let cmd = try InitCommand.parse([
          "Demo",
          "--path", "/does/not/exist/swiflow-test-\(UUID().uuidString)",
          "--swiflow-source", "/abs/path/to/swiflow",
      ])
      await #expect(throws: ValidationError.self) {
          try await cmd.run()
      }
  }
  ```

- [ ] **Step 4: Run the tests and confirm exactly one failure**

  ```bash
  swift test --filter "InitCommand argv"
  ```

  Expected output: `missingSwiflowSource` **FAILS** (parse succeeds, no error thrown — the default `"../.."` is still there). `defaultPath` and `flags` pass. Everything else in the suite passes.

  If more than one test fails, stop and investigate before proceeding.

- [ ] **Step 5: Commit the failing tests**

  ```bash
  git add Tests/SwiflowCLITests/InitCommandTests.swift
  git commit -m "test(init): expect ValidationError when --swiflow-source is missing"
  ```

---

### Task 2: Fix `InitCommand` — make `--swiflow-source` required

**Files:**
- Modify: `Sources/SwiflowCLI/Commands/InitCommand.swift`

- [ ] **Step 1: Change the `swiflowSource` option type and help text**

  Locate the `@Option` block for `--swiflow-source` (lines 41–53). Replace the entire block:

  ```swift
  @Option(
      name: .customLong("swiflow-source"),
      help: ArgumentHelp(
          "Path the generated project uses for its Swiflow dependency.",
          discussion: """
              Required until Swiflow has a public release. Pass the absolute or \
              relative path to your local Swiflow clone.
              Example: --swiflow-source /path/to/swiflow
              """
      )
  )
  var swiflowSource: String?
  ```

  The key changes: type is now `String?` (no default), and the stale "After Phase 4 publishes Swiflow" discussion is removed.

- [ ] **Step 2: Add `validate()` immediately after the properties, before `run()`**

  Insert this method between the last property and `func run()`:

  ```swift
  mutating func validate() throws {
      if swiflowSource == nil {
          throw ValidationError("""
              --swiflow-source is required. Swiflow has no public release yet.
              Pass the path to your local Swiflow clone:
                swiflow init \(name) --swiflow-source /path/to/swiflow
              """)
      }
  }
  ```

  ArgumentParser calls `validate()` automatically after parsing and before `run()`. The `mutating` keyword is required by the `ParsableCommand` protocol conformance.

- [ ] **Step 3: Force-unwrap `swiflowSource` in `run()`**

  Locate the call to `ProjectWriter.writeProject(...)` inside `run()`. Change:

  ```swift
  swiflowSource: swiflowSource,
  ```

  to:

  ```swift
  swiflowSource: swiflowSource!,   // validate() guarantees non-nil
  ```

- [ ] **Step 4: Run the full `InitCommand` test suite**

  ```bash
  swift test --filter InitCommandTests
  ```

  Expected: all tests **PASS**. If any fail, fix before proceeding.

- [ ] **Step 5: Run the full test suite to check for regressions**

  ```bash
  swift test --skip DevCommandTests --skip BuildCommandTests
  ```

  (The E2E suites require a WASM SDK and take ~3 minutes each — skip for this fast check.)

  Expected: all 463 non-E2E tests pass.

- [ ] **Step 6: Commit**

  ```bash
  git add Sources/SwiflowCLI/Commands/InitCommand.swift
  git commit -m "fix(init): make --swiflow-source required; fail fast with helpful error"
  ```
