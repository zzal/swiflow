# Swiflow Phase 2b.3 — Cosmetics Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the three cosmetic observations the Phase 2b.1 cross-task review surfaced (template path-comment, DriverEmbedder access level, WasmSDKProbe stderr swallow). Bundle into a single commit — these are independent, low-risk, non-behavioral fixes.

**Architecture:** No new types, no new public surface. One template string edit (with synced example), one access-modifier flip, one new `WasmSDKProbeError` thrown on non-zero `swift sdk list` exit (replacing the silent `return []`). `BuildCommand` catches the new error and rewraps as `BuildCommandError.wasmSDKListFailed(exitCode:stderr:)` so the user gets the actual stderr instead of a misleading "no WASM SDK installed" message when their Swift binary is the actual culprit.

**Tech Stack:** Swift 6.0, Swift Testing, swift-argument-parser. No new dependencies.

---

## File Structure

**Edit (3 source files):**
- `Sources/SwiflowCLI/Templates/Templates.swift` — line 88, change `rawAppSwift` first-line comment from `// examples/{{NAME}}/Sources/App/App.swift` to `// Sources/App/App.swift` (project-root-relative; doesn't lie when the project lives outside `examples/`).
- `Sources/SwiflowCLI/DriverEmbedder.swift` — lines 10 and 19, drop the `public` modifier on `enum DriverEmbedder` and its `static func swiftSource(forJSSource:)`. The target is an executable; `public` has no linkage effect and misleads readers into thinking external callers exist.
- `Sources/SwiflowCLI/Toolchain/WasmSDKProbe.swift` — lines 27-30, introduce `WasmSDKProbeError.sdkSubcommandFailed(exitCode:stderr:)` and `throw` it on non-zero exit instead of swallowing into `return []`. Distinguishes "swift sdk list ran fine but no WASM SDK installed" from "swift sdk list failed (toolchain too old, broken install, etc.)".

**Edit (1 example file, kept in sync):**
- `examples/HelloWorld/Sources/App/App.swift` — line 1, must match the new template output for `TemplatesTests.appSwiftMatchesExample` to pass.

**Edit (1 command file, error wiring):**
- `Sources/SwiflowCLI/Commands/BuildCommand.swift` — add `BuildCommandError.wasmSDKListFailed(exitCode:stderr:)` case (with description); in `run()`, wrap `probe.list()` in `do/catch` that translates `WasmSDKProbeError.sdkSubcommandFailed` into `ValidationError(BuildCommandError.wasmSDKListFailed)`. Keeps `noWasmSDKInstalled` reserved for the legitimate "list succeeded but empty" case.

**Edit (2 test files):**
- `Tests/SwiflowCLITests/WasmSDKProbeTests.swift` — add one `@Test` covering the new throwing path.
- `Tests/SwiflowCLITests/BuildCommandTests.swift` — add the new `BuildCommandError.wasmSDKListFailed` description assertion alongside the existing `projectPathNotFound` one.

**No changes needed:**
- `scripts/embed-driver.swift` — it re-implements the wrapping inline (the comment explains why); access level on `DriverEmbedder` is irrelevant to it.
- `Tests/SwiflowCLITests/DriverEmbedderTests.swift` — uses `@testable import SwiflowCLI` already; internal access still resolves.
- `Tests/SwiflowCLITests/TemplatesTests.swift` — existing `appSwiftMatchesExample` is the byte-equality safety net for the path-comment change; it will fail after the example edit and pass again after the template edit.

---

## Task 1: Bundle Phase 2b.3 cosmetics into one commit

**Files:**
- Modify: `Sources/SwiflowCLI/Templates/Templates.swift:88`
- Modify: `examples/HelloWorld/Sources/App/App.swift:1`
- Modify: `Sources/SwiflowCLI/DriverEmbedder.swift:10,19`
- Modify: `Sources/SwiflowCLI/Toolchain/WasmSDKProbe.swift:9,19-31`
- Modify: `Sources/SwiflowCLI/Commands/BuildCommand.swift:14-36,118-129`
- Modify: `Tests/SwiflowCLITests/WasmSDKProbeTests.swift` (append one `@Test`)
- Modify: `Tests/SwiflowCLITests/BuildCommandTests.swift` (append one `@Test`)

Run from repo root: `./`.

- [ ] **Step 1: Add the failing WasmSDKProbe error test**

  Append this `@Test` inside the `WasmSDKProbeTests` suite in `Tests/SwiflowCLITests/WasmSDKProbeTests.swift` (before the closing `}` of the struct):

  ```swift
      @Test("list() throws WasmSDKProbeError.sdkSubcommandFailed on non-zero exit, carrying stderr")
      func listThrowsOnNonZeroExit() {
          let stub = StubProcessRunner(
              stubbedExitCode: 2,
              stubbedStandardOutput: nil,
              stubbedStandardError: "error: unknown subcommand 'sdk'\n"
          )
          let probe = WasmSDKProbe(runner: stub, swiftExecutable: URL(fileURLWithPath: "/usr/bin/swift"))
          #expect(throws: WasmSDKProbeError.sdkSubcommandFailed(
              exitCode: 2,
              stderr: "error: unknown subcommand 'sdk'\n"
          )) {
              _ = try probe.list()
          }
      }
  ```

- [ ] **Step 2: Run the test, confirm it fails to compile**

  Run: `swift test --filter WasmSDKProbeTests/listThrowsOnNonZeroExit 2>&1 | tail -20`

  Expected: build error — `WasmSDKProbeError` is undefined. (That's the next step.)

- [ ] **Step 3: Introduce `WasmSDKProbeError` and make `list()` throw**

  Edit `Sources/SwiflowCLI/Toolchain/WasmSDKProbe.swift`. Add the error type just below `import Foundation` (above the `struct WasmSDKProbe` declaration):

  ```swift
  /// Errors thrown by `WasmSDKProbe.list()`. A non-zero exit from
  /// `swift sdk list` is distinct from "list returned no WASM SDKs":
  /// the former indicates a broken toolchain (e.g., Swift too old to know
  /// the `sdk` subcommand); the latter is a legitimate state callers handle
  /// by prompting the user to `swift sdk install`. Carrying stderr lets
  /// callers surface the real diagnostic instead of the misleading
  /// "no WASM SDK installed".
  enum WasmSDKProbeError: Error, Equatable {
      case sdkSubcommandFailed(exitCode: Int32, stderr: String?)
  }
  ```

  Then replace the body of `func list() throws -> [String]` (lines 19-31) with:

  ```swift
      /// Runs `swift sdk list` and returns the parsed WASM SDK identifiers.
      ///
      /// Throws `WasmSDKProbeError.sdkSubcommandFailed` when the subprocess
      /// exits non-zero. A successful run with no `_wasm` suffix in the
      /// listing returns `[]` (the caller decides what that means).
      func list() throws -> [String] {
          let result = try runner.run(
              executable: swiftExecutable,
              arguments: ["sdk", "list"],
              workingDirectory: nil,
              environment: nil,
              captureOutput: true
          )
          guard result.exitCode == 0 else {
              throw WasmSDKProbeError.sdkSubcommandFailed(
                  exitCode: result.exitCode,
                  stderr: result.standardError
              )
          }
          let stdout = result.standardOutput ?? ""
          return Self.parseSDKList(stdout)
      }
  ```

- [ ] **Step 4: Run the new test plus the existing WasmSDKProbe suite — confirm pass**

  Run: `swift test --filter WasmSDKProbeTests 2>&1 | tail -20`

  Expected: all WasmSDKProbeTests pass (existing 7 + new 1 = 8).

- [ ] **Step 5: Wire the error through BuildCommand**

  Edit `Sources/SwiflowCLI/Commands/BuildCommand.swift`. Add a new case to `BuildCommandError` (line 14 area) and its description:

  ```swift
  enum BuildCommandError: Error, Equatable, CustomStringConvertible {
      case swiftNotOnPath
      case noWasmSDKInstalled
      case wasmSDKListFailed(exitCode: Int32, stderr: String?)
      case swiftPackageJSFailed(exitCode: Int32)
      case projectPathNotFound(URL)

      var description: String {
          switch self {
          case .swiftNotOnPath:
              return "swift is not on PATH. Install Swift from https://swift.org/install and try again."
          case .noWasmSDKInstalled:
              return """
                  No WASM Swift SDK is installed. Run:
                      swift sdk install <SDK URL for your Swift version>
                  with a URL from https://swift.org/install (look for the WebAssembly SDK).
                  """
          case .wasmSDKListFailed(let code, let stderr):
              let trimmed = stderr?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
              let trailer = trimmed.isEmpty ? "" : "\n\nDetails from swift:\n\(trimmed)"
              return """
                  `swift sdk list` failed with exit code \(code). \
                  Your Swift toolchain may not support the `sdk` subcommand \
                  (it landed in Swift 5.9). Verify with `swift --version`.\(trailer)
                  """
          case .swiftPackageJSFailed(let code):
              return "swift package js failed with exit code \(code). See output above."
          case .projectPathNotFound(let url):
              return "project path does not exist or is not a directory: \(url.path)"
          }
      }
  }
  ```

  Then in `BuildCommand.run()`, replace the SDK-probe block (lines ~119-129 — the `else { let probe = ... }` arm) with:

  ```swift
          // 2. Resolve the WASM SDK ID — either user-supplied or auto-picked.
          let sdk: String
          if let userSDK = swiftSDK {
              sdk = userSDK
          } else {
              let probe = WasmSDKProbe(runner: runner, swiftExecutable: swift)
              let installed: [String]
              do {
                  installed = try probe.list()
              } catch let WasmSDKProbeError.sdkSubcommandFailed(exitCode, stderr) {
                  throw ValidationError(String(describing: BuildCommandError.wasmSDKListFailed(
                      exitCode: exitCode,
                      stderr: stderr
                  )))
              }
              guard let firstInstalled = installed.first else {
                  throw ValidationError(String(describing: BuildCommandError.noWasmSDKInstalled))
              }
              sdk = firstInstalled
          }
  ```

- [ ] **Step 6: Add the BuildCommandError description test**

  Append this `@Test` inside `BuildCommandArgvTests` in `Tests/SwiflowCLITests/BuildCommandTests.swift` (just before the closing `}` of the struct, right after `projectPathNotFoundDescription`):

  ```swift
      @Test("BuildCommandError.wasmSDKListFailed surfaces exit code and stderr")
      func wasmSDKListFailedDescription() {
          let error = BuildCommandError.wasmSDKListFailed(
              exitCode: 2,
              stderr: "error: unknown subcommand 'sdk'\n"
          )
          let desc = String(describing: error)
          #expect(desc.contains("exit code 2"))
          #expect(desc.contains("unknown subcommand 'sdk'"))
          #expect(desc.contains("`sdk` subcommand"))
      }

      @Test("BuildCommandError.wasmSDKListFailed renders cleanly when stderr is nil")
      func wasmSDKListFailedNilStderr() {
          let error = BuildCommandError.wasmSDKListFailed(exitCode: 1, stderr: nil)
          let desc = String(describing: error)
          #expect(desc.contains("exit code 1"))
          // Should not contain the "Details from swift:" trailer when stderr is missing.
          #expect(!desc.contains("Details from swift:"))
      }
  ```

- [ ] **Step 7: Drop the `public` modifier on DriverEmbedder**

  Edit `Sources/SwiflowCLI/DriverEmbedder.swift`.

  Line 10 — change:
  ```swift
  public enum DriverEmbedder {
  ```
  to:
  ```swift
  enum DriverEmbedder {
  ```

  Line 19 — change:
  ```swift
      public static func swiftSource(forJSSource js: String) -> String {
  ```
  to:
  ```swift
      static func swiftSource(forJSSource js: String) -> String {
  ```

  (Tests use `@testable import SwiflowCLI`; internal access remains visible to them. The codegen script `scripts/embed-driver.swift` doesn't import this file — it reimplements the wrapping inline by design, per its own comment.)

- [ ] **Step 8: Fix the App.swift template path comment + sync the example**

  First edit the example (this will make `TemplatesTests.appSwiftMatchesExample` start failing). In `examples/HelloWorld/Sources/App/App.swift`, line 1, change:
  ```swift
  // examples/HelloWorld/Sources/App/App.swift
  ```
  to:
  ```swift
  // Sources/App/App.swift
  ```

  Now edit the template. In `Sources/SwiflowCLI/Templates/Templates.swift`, line 88 (inside the `rawAppSwift` raw-string literal), change:
  ```swift
      // examples/{{NAME}}/Sources/App/App.swift
  ```
  to:
  ```swift
      // Sources/App/App.swift
  ```

  Rationale: the comment names the path of the file from the project root. For the example project (root = `examples/HelloWorld/`), the path-from-root IS `Sources/App/App.swift`. For a user's `swiflow init MyApp` project (root = `~/whatever/MyApp/`), the path is also `Sources/App/App.swift`. No more lying about where the file lives.

- [ ] **Step 9: Run the full test suite — confirm 175 → 177 pass**

  Run: `swift test 2>&1 | tail -20`

  Expected: all tests pass. Test count: 175 (after Phase 2b.2) + 2 new (Step 6 added two; Step 1 added one; Step 7 changed no tests; Step 8 keeps the existing byte-equality test green via paired edits) = **178 passing** if the math holds. (Plan check: `+1` from Step 1, `+2` from Step 6, `+0` elsewhere → +3 total, landing at 178. If the actual count differs by one, suspect a test that was a single `@Test func` with multiple `#expect` lines being miscounted in the plan.)

  Watch specifically that these stay green:
  - `TemplatesTests/appSwiftMatchesExample` — paired template+example edit must produce identical strings.
  - `DriverEmbedderTests/wrapsJSAsSwiftConstant` and `embeddedDriverMatchesDriverEmbedderOutput` — internal access via `@testable import` must still resolve.
  - `BuildCommandArgvTests/*` — error enum gained a case but no existing case changed; pattern matches in tests should be unaffected.

- [ ] **Step 10: Confirm regenerating the embedded driver is a no-op**

  Run: `swift scripts/embed-driver.swift && git diff --stat Sources/SwiflowCLI/EmbeddedDriver.swift 2>&1`

  Expected: `wrote .../EmbeddedDriver.swift (NNNN bytes)` and `git diff --stat` shows zero changes. (The script's inline wrapping should already match what's committed; this just verifies we didn't accidentally break the codegen by editing `DriverEmbedder.swift`.)

- [ ] **Step 11: Stage and commit all changes in one commit**

  ```bash
  git add Sources/SwiflowCLI/Templates/Templates.swift \
          examples/HelloWorld/Sources/App/App.swift \
          Sources/SwiflowCLI/DriverEmbedder.swift \
          Sources/SwiflowCLI/Toolchain/WasmSDKProbe.swift \
          Sources/SwiflowCLI/Commands/BuildCommand.swift \
          Tests/SwiflowCLITests/WasmSDKProbeTests.swift \
          Tests/SwiflowCLITests/BuildCommandTests.swift
  git commit -m "$(cat <<'EOF'
  chore(cli): Phase 2b.3 cosmetics — path comment, access level, stderr surfacing

  Three independent low-risk fixes from the Phase 2b.1 cross-task review:

  1. Templates: `rawAppSwift` first-line comment no longer hardcodes the
     `examples/` prefix. After `swiflow init MyApp` the generated file's
     path-from-root is `Sources/App/App.swift`, which is the same for the
     example project (whose root is `examples/HelloWorld/`). Example file
     synced so the byte-equality test stays green.

  2. DriverEmbedder: drop `public` modifier — the target is an executable,
     so `public` has no linkage effect and misleads readers into thinking
     external callers exist. Tests use `@testable import` already.

  3. WasmSDKProbe.list(): throw `WasmSDKProbeError.sdkSubcommandFailed`
     (carrying exit code + stderr) on non-zero exit instead of swallowing
     into `return []`. BuildCommand catches and surfaces via the new
     `BuildCommandError.wasmSDKListFailed` case, so a broken Swift toolchain
     no longer masquerades as "no WASM SDK installed".

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

  Verify with `git log -1 --stat` afterward: expect the seven listed files in one commit.

---

## Verification

After the commit:

```bash
swift test 2>&1 | tail -5
# Expected: ✔ Test run with N tests passed
```

Manual error-path spot-check (optional, requires Swift 5.8 or a Swift binary without `sdk` subcommand):

```bash
swift build --product swiflow
./.build/debug/swiflow build --path /tmp/some-project
# With the OLD code: "No WASM Swift SDK is installed..." (misleading)
# With the NEW code: "`swift sdk list` failed with exit code 1. Your Swift
#  toolchain may not support the `sdk` subcommand (it landed in Swift 5.9).
#  Verify with `swift --version`.
#  Details from swift: error: unknown subcommand 'sdk'"
```

---

## Out of Scope

Explicit non-goals for this phase, deferred to later phases per the Phase 2b.1/2b.2 review notes:

- `scripts/embed-driver.swift` consolidation (script duplicates DriverEmbedder logic by design — the freshness test catches drift; restructuring is Phase 4 territory).
- Adding stderr capture to `BuildInvocation` (the build itself uses `captureOutput: false` to stream to the user — different concern from the probe).
- Localizing error messages (English-only is fine for Phase 2; if and when a contributor base outside English emerges, revisit).
- Linux/CI verification of the new error path — local macOS run is sufficient because the change is pure value-shaping, no platform-specific code.
- Phase 2c (dev server + file watcher + WebSocket reload) — separate plan after 2b.3 lands.

---

## Self-Review Notes

- **Spec coverage:** All three user-requested observations covered (rawAppSwift path → Step 8; DriverEmbedder access → Step 7; WasmSDKProbe stderr → Steps 1-6). All in one commit per the user's constraint (Step 11).
- **Placeholder scan:** None. Every code block is the actual code to paste; every command is the actual command to run; every expected output is concrete.
- **Type consistency:** `WasmSDKProbeError.sdkSubcommandFailed(exitCode: Int32, stderr: String?)` used identically in WasmSDKProbe.swift, the new probe test, and the BuildCommand `catch` clause. `BuildCommandError.wasmSDKListFailed(exitCode: Int32, stderr: String?)` matches across the enum, description, BuildCommand `throw`, and both new BuildCommand tests. `ValidationError(String(describing:))` pattern matches the existing `noWasmSDKInstalled` and `projectPathNotFound` paths in BuildCommand.run().
- **Risk:** The pattern-match `catch let WasmSDKProbeError.sdkSubcommandFailed(exitCode, stderr)` in BuildCommand has the `WasmSDKProbeError.` prefix to satisfy the compiler when the catch-clause has no `as` annotation — verified against the existing `catch let error as BuildCommandError` style two lines below it (different style, same effect; choose the one that's more readable for the team).
