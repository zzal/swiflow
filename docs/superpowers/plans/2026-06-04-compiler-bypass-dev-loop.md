# Compiler-Bypass Dev Loop (Lever 2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cut the `swiflow dev` hot-rebuild from ~12s to ~1.6s by capturing SwiftPM's own `swiftc` + `wasm-ld` commands from one verbose build and replaying just those two on each subsequent save, with a staleness key that self-heals when the inputs change.

**Architecture:** A staleness-aware `BypassRebuilder` wraps the shipped Lever 1 units (`RawWasmBuildInvocation`, `WasmArtifactCopier`). On each save it either replays the cached commands or runs one full `swift build --product App -v` that both produces the wasm and yields the commands to parse. Loop-owned `inout BypassState` holds the captured commands across saves, preserving the existing `Sendable`-value-type + per-call-`ProcessRunner` idiom.

**Tech Stack:** Swift 6, Swift Testing (`import Testing`), `Foundation.Process` via the `ProcessRunner` seam, SwiftPM WASM cross-compile.

**Spec:** `docs/superpowers/specs/2026-06-04-compiler-bypass-dev-loop-design.md`. **Evidence:** `docs/perf/2026-06-04-wasm-hotswap-spike.md`.

---

## Conventions for the implementer (read once)

- **Tests:** Swift Testing — `@Suite`, `@Test`, `#expect`, `#require`, `Issue.record`, `.enabled(if:)`, `.timeLimit(.minutes(_:))`. NOT XCTest.
- **Run a single suite:** `swift test --filter <SuiteOrTestName>`. Run all CLI tests: `swift test --filter SwiflowCLITests`.
- **`ProcessRunner` seam:** `protocol ProcessRunner: AnyObject { func run(executable:arguments:workingDirectory:environment:captureOutput:) throws -> ProcessResult }`. `ProcessResult { exitCode: Int32; standardOutput: String?; standardError: String? }`. `StubProcessRunner(stubbedExitCode:stubbedStandardOutput:stubbedStandardError:)` records `.calls` where each `Call` has `executable / arguments / workingDirectory / environment` (NOT `captureOutput`). It returns the SAME stubbed output for every call.
- **Existing error:** `BuildCommandError.swiftBuildFailed(exitCode: Int32)` already exists (in `Commands/BuildCommand.swift`); reuse it for non-zero builds/replays. Do NOT invent a new error.
- **Reused, do NOT modify:** `RawWasmBuildInvocation`, `WasmArtifactLocator`, `WasmArtifactCopier` in `Sources/SwiflowCLI/DevServer/FastRebuild.swift`.
- **SourceKit/IDE "No such module 'Testing'" / "cannot find type" diagnostics are STALE** — verify ONLY with `swift build` / `swift test`, never trust the editor.
- **The repeated `Internal Error: DecodingError … unexpected end of file` line during builds is benign macro-plugin-server noise** — ignore it; the build is fine if it ends with `Build complete!`.
- **git:** commit on the CURRENT branch only. Do NOT run `git checkout`/`switch`/`branch`/`stash`/`reset`/`restore` (shared working tree). The controller created the feature branch.
- All new production code goes in ONE new file: `Sources/SwiflowCLI/DevServer/CompilerBypass.swift`. All new tests in ONE new file: `Tests/SwiflowCLITests/DevServer/CompilerBypassTests.swift`. Plus one fixture file and the `ProcessRunner` + `DevCommand` edits.

---

## Task 1: Concurrent pipe drain in `SystemProcessRunner` (prerequisite)

A verbose `swift build -v` emits MBs to BOTH stdout and stderr. The current `captureOutput: true` path reads stdout-to-end then stderr (`ProcessRunner.swift:91-92`); `readDataToEndOfFile()` on the first pipe blocks until child exit, while the child blocks writing the full second pipe — **deadlock**. Drain both pipes concurrently.

**Files:**
- Modify: `Sources/SwiflowCLI/Process/ProcessRunner.swift` (the `captureOutput` drain region, ~lines 84-96)
- Test: `Tests/SwiflowCLITests/Process/ProcessRunnerDrainTests.swift` (create)

- [ ] **Step 1: Write the failing test**

Create `Tests/SwiflowCLITests/Process/ProcessRunnerDrainTests.swift`:

```swift
import Foundation
import Testing
@testable import SwiflowCLI

@Suite("SystemProcessRunner concurrent drain")
struct ProcessRunnerDrainTests {

    // A child that interleaves >64 KiB to BOTH stdout and stderr. With a
    // sequential stdout-then-stderr drain this deadlocks; with concurrent
    // drain it completes. ~6000 lines × ~20 bytes ≫ the 64 KiB pipe buffer.
    @Test("Captures large output on both streams without deadlocking", .timeLimit(.minutes(1)))
    func drainsBothStreams() throws {
        let runner = SystemProcessRunner()
        let script = "i=0; while [ $i -lt 6000 ]; do echo out-line-$i; echo err-line-$i 1>&2; i=$((i+1)); done"
        let result = try runner.run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script],
            workingDirectory: nil,
            environment: nil,
            captureOutput: true
        )
        #expect(result.exitCode == 0)
        let out = try #require(result.standardOutput)
        let err = try #require(result.standardError)
        #expect(out.contains("out-line-0"))
        #expect(out.contains("out-line-5999"))
        #expect(err.contains("err-line-0"))
        #expect(err.contains("err-line-5999"))
    }
}
```

- [ ] **Step 2: Run it to confirm it hangs/fails against the current code**

Run: `swift test --filter ProcessRunnerDrainTests`
Expected: the test exceeds the time limit (deadlock) and is reported as a failure. (If your machine's pipe buffer is unusually large it may pass — proceed regardless; Step 3 makes it correct by construction.)

- [ ] **Step 3: Implement concurrent drain**

In `Sources/SwiflowCLI/Process/ProcessRunner.swift`, replace the sequential read (the two `readDataToEndOfFile()` lines and the surrounding `Limitation:` comment, currently ~lines 84-93) with a concurrent drain. Add this small helper class near the top of the file (after the `import Foundation`):

```swift
/// Drains one FileHandle to completion on a background queue. `@unchecked
/// Sendable` is sound here: the handle and buffer are touched only inside
/// `drain()`, and the result is read only after `DispatchGroup.wait()`
/// establishes happens-before.
private final class FileHandleDrain: @unchecked Sendable {
    let handle: FileHandle
    var data = Data()
    init(_ handle: FileHandle) { self.handle = handle }
    func drain() { data = handle.readDataToEndOfFile() }
}
```

Then in `run(...)`, replace the old drain block with:

```swift
        // Drain BOTH pipes concurrently before waitUntilExit(). A sequential
        // stdout-then-stderr read deadlocks when the child fills the second
        // pipe's buffer (~64 KiB) while we're still blocked on the first —
        // exactly what a verbose `swift build -v` does. One reader per pipe.
        let outDrain = outPipe.map { FileHandleDrain($0.fileHandleForReading) }
        let errDrain = errPipe.map { FileHandleDrain($0.fileHandleForReading) }
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "swiflow.procrunner.drain", attributes: .concurrent)
        if let outDrain { queue.async(group: group) { outDrain.drain() } }
        if let errDrain { queue.async(group: group) { errDrain.drain() } }
        group.wait()
        process.waitUntilExit()

        let stdout = outDrain.flatMap { String(data: $0.data, encoding: .utf8) }
        let stderr = errDrain.flatMap { String(data: $0.data, encoding: .utf8) }
```

Leave the `return ProcessResult(...)` below it unchanged.

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter ProcessRunnerDrainTests`
Expected: PASS (well under the 1-minute limit).

- [ ] **Step 5: Verify no regression in existing ProcessRunner callers**

Run: `swift build && swift test --filter SwiflowCLITests`
Expected: builds; existing suites pass (the small-output capture call sites — `swift sdk list`, `--show-bin-path` — behave identically). `OnChangeStorageTests` may flake ~1/3 under parallel runs; re-run in isolation to confirm it's the known flake, not a regression.

- [ ] **Step 6: Commit**

```bash
git add Sources/SwiflowCLI/Process/ProcessRunner.swift Tests/SwiflowCLITests/Process/ProcessRunnerDrainTests.swift
git commit -m "fix(cli): drain ProcessRunner stdout+stderr concurrently to avoid deadlock on large dual-stream output"
```

---

## Task 2: `ResolvedCommand` + `CapturingWasmBuildInvocation`

The capturing build: `swift build --swift-sdk <id> --product App -v` with `captureOutput: true`, returning combined stdout+stderr for the parser. `ResolvedCommand` is the value type for a replayable command.

**Files:**
- Create: `Sources/SwiflowCLI/DevServer/CompilerBypass.swift`
- Test: `Tests/SwiflowCLITests/DevServer/CompilerBypassTests.swift` (create)

- [ ] **Step 1: Write the failing test**

Create `Tests/SwiflowCLITests/DevServer/CompilerBypassTests.swift`:

```swift
import Foundation
import Testing
@testable import SwiflowCLI

@Suite("CapturingWasmBuildInvocation")
struct CapturingWasmBuildInvocationTests {

    @Test("Composes `swift build --swift-sdk <id> --product App -v`")
    func argv() throws {
        let stub = StubProcessRunner(stubbedExitCode: 0, stubbedStandardOutput: "ok", stubbedStandardError: nil)
        let inv = CapturingWasmBuildInvocation(
            swiftExecutable: URL(fileURLWithPath: "/usr/bin/swift"),
            projectPath: URL(fileURLWithPath: "/tmp/demo"),
            swiftSDK: "swift-6.3-RELEASE_wasm",
            toolchainBundleID: nil
        )
        let output = try inv.run(using: stub)
        #expect(stub.calls.count == 1)
        #expect(stub.calls[0].arguments == [
            "build", "--swift-sdk", "swift-6.3-RELEASE_wasm", "--product", "App", "-v",
        ])
        #expect(stub.calls[0].workingDirectory?.path == "/tmp/demo")
        #expect(output.contains("ok"))            // returns captured output
    }

    @Test("Returns combined stdout + stderr (verbose lines may land on either)")
    func combinesStreams() throws {
        let stub = StubProcessRunner(stubbedExitCode: 0, stubbedStandardOutput: "OUT", stubbedStandardError: "ERR")
        let inv = CapturingWasmBuildInvocation(
            swiftExecutable: URL(fileURLWithPath: "/usr/bin/swift"),
            projectPath: URL(fileURLWithPath: "/tmp/demo"),
            swiftSDK: "swift-6.3-RELEASE_wasm",
            toolchainBundleID: "org.swift.63"
        )
        let output = try inv.run(using: stub)
        #expect(output.contains("OUT"))
        #expect(output.contains("ERR"))
        #expect(stub.calls[0].environment?["TOOLCHAINS"] == "org.swift.63")
    }

    @Test("Non-zero exit throws swiftBuildFailed")
    func throwsOnFailure() {
        let stub = StubProcessRunner(stubbedExitCode: 9)
        let inv = CapturingWasmBuildInvocation(
            swiftExecutable: URL(fileURLWithPath: "/usr/bin/swift"),
            projectPath: URL(fileURLWithPath: "/tmp/demo"),
            swiftSDK: "swift-6.3-RELEASE_wasm",
            toolchainBundleID: nil
        )
        #expect(throws: BuildCommandError.swiftBuildFailed(exitCode: 9)) {
            _ = try inv.run(using: stub)
        }
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `swift test --filter CapturingWasmBuildInvocationTests`
Expected: FAIL — `cannot find 'CapturingWasmBuildInvocation' in scope` / `ResolvedCommand`.

- [ ] **Step 3: Create the file with `ResolvedCommand` + `CapturingWasmBuildInvocation`**

Create `Sources/SwiflowCLI/DevServer/CompilerBypass.swift`:

```swift
// Sources/SwiflowCLI/DevServer/CompilerBypass.swift
//
// Dev-only "compiler bypass" (Lever 2): on each save, replay SwiftPM's own
// swiftc + wasm-ld commands directly, skipping the ~9s SwiftPM orchestration
// overhead that `swift build` pays on every invocation. Commands are captured
// once from a verbose build and re-captured when the app's source/import set
// or the package manifest changes. See
// docs/superpowers/specs/2026-06-04-compiler-bypass-dev-loop-design.md.

import Foundation

/// One replayable command: an executable plus its full argv.
struct ResolvedCommand: Sendable, Equatable {
    let executable: URL
    let arguments: [String]
}

/// `swift build --swift-sdk <id> --product App -v` with output captured so the
/// emitted swiftc/wasm-ld lines can be parsed. Sibling of `RawWasmBuildInvocation`;
/// the name signals intent (capturing the commands is the purpose, `-v` the means).
struct CapturingWasmBuildInvocation: Sendable {
    let swiftExecutable: URL
    let projectPath: URL
    let swiftSDK: String
    let toolchainBundleID: String?

    func composeArguments() -> [String] {
        ["build", "--swift-sdk", swiftSDK, "--product", "App", "-v"]
    }

    /// Runs the build (which also produces the wasm) and returns the combined
    /// stdout+stderr — SwiftPM's verbose command lines can appear on either
    /// stream, and the version may vary, so we hand the parser both.
    func run(using runner: ProcessRunner) throws -> String {
        let environment: [String: String]? = toolchainBundleID.map { ["TOOLCHAINS": $0] }
        let result = try runner.run(
            executable: swiftExecutable,
            arguments: composeArguments(),
            workingDirectory: projectPath,
            environment: environment,
            captureOutput: true
        )
        if result.exitCode != 0 {
            throw BuildCommandError.swiftBuildFailed(exitCode: result.exitCode)
        }
        return (result.standardOutput ?? "") + "\n" + (result.standardError ?? "")
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter CapturingWasmBuildInvocationTests`
Expected: PASS (all 3).

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiflowCLI/DevServer/CompilerBypass.swift Tests/SwiflowCLITests/DevServer/CompilerBypassTests.swift
git commit -m "feat(cli): add CapturingWasmBuildInvocation + ResolvedCommand for the bypass loop"
```

---

## Task 3: `BuildCommandParser` (+ shell tokenizer + fixture)

Parse the verbose output into the App-module `-c` compile command and the `App.wasm` link command. There are **two** `-module-name App … wasm32` swiftc jobs (an `-emit-module` job and the `-c` compile job); select the `-c` job. Return nil if any anchor is absent or the compile job is ambiguous.

**Files:**
- Modify: `Sources/SwiflowCLI/DevServer/CompilerBypass.swift`
- Create: `Tests/SwiflowCLITests/Fixtures/swift-build-verbose-sample.txt`
- Test: `Tests/SwiflowCLITests/DevServer/CompilerBypassTests.swift`

- [ ] **Step 1: Create the fixture**

Create `Tests/SwiflowCLITests/Fixtures/swift-build-verbose-sample.txt` (synthetic but structurally faithful — a host macro-plugin line, the App `-emit-module` job, the App `-c` job with a space-quoted `-I` path to exercise the tokenizer, the clang link line, and the nested wasm-ld decoy):

```
/tc/usr/bin/swiftc -module-name SwiflowMacrosPlugin -target arm64-apple-macosx10.15 -c /work/Macros.swift -o /work/.build/host/Macros.o
/tc/usr/bin/swiftc -module-name App -target wasm32-unknown-wasip1 -emit-module -emit-module-path /work/.build/wasm32-unknown-wasip1/debug/Modules/App.swiftmodule /work/Sources/App/App.swift
/tc/usr/bin/swiftc -module-name App -target wasm32-unknown-wasip1 -I "/work/My Headers/inc" -c /work/Sources/App/App.swift -primary-file /work/Sources/App/App.swift -o /work/.build/wasm32-unknown-wasip1/debug/App.build/App.swift.o
/tc/usr/bin/clang -target wasm32-unknown-wasip1 -o /work/.build/wasm32-unknown-wasip1/debug/App.wasm @/work/.build/wasm32-unknown-wasip1/debug/App.product/Objects.LinkFileList -L/tc/lib
"/tc/usr/bin/wasm-ld" -m wasm32 -o /work/.build/wasm32-unknown-wasip1/debug/App.wasm /work/objs/a.o
Build complete! (1.62s)
```

- [ ] **Step 2: Write the failing tests**

Append to `Tests/SwiflowCLITests/DevServer/CompilerBypassTests.swift`:

```swift
@Suite("BuildCommandParser")
struct BuildCommandParserTests {

    static var sample: String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()                       // DevServer
            .deletingLastPathComponent()                       // SwiflowCLITests
            .appendingPathComponent("Fixtures/swift-build-verbose-sample.txt")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    @Test("Selects the -c App wasm compile job (not -emit-module, not the host line)")
    func picksCompileJob() throws {
        let parsed = try #require(BuildCommandParser.parse(verboseOutput: Self.sample, appModule: "App"))
        #expect(parsed.compile.executable.path == "/tc/usr/bin/swiftc")
        #expect(parsed.compile.arguments.contains("-c"))
        #expect(parsed.compile.arguments.contains("-module-name"))
        #expect(parsed.compile.arguments.contains("App"))
        #expect(!parsed.compile.arguments.contains("-emit-module"))   // not the module-emit job
        // Quoted "-I" path survived tokenization as a single argument.
        #expect(parsed.compile.arguments.contains("/work/My Headers/inc"))
    }

    @Test("Selects the clang App.wasm link line (not the nested wasm-ld)")
    func picksLinkJob() throws {
        let parsed = try #require(BuildCommandParser.parse(verboseOutput: Self.sample, appModule: "App"))
        #expect(parsed.link.executable.path == "/tc/usr/bin/clang")
        #expect(parsed.link.arguments.contains("-o"))
        #expect(parsed.link.arguments.contains { $0.hasSuffix("/App.wasm") })
    }

    @Test("Returns nil when the compile job is absent")
    func nilWhenNoCompile() {
        let noCompile = """
        /tc/usr/bin/clang -target wasm32-unknown-wasip1 -o /work/App.wasm @/work/list
        """
        #expect(BuildCommandParser.parse(verboseOutput: noCompile, appModule: "App") == nil)
    }

    @Test("Returns nil when two object-emitting App compile jobs are ambiguous")
    func nilWhenAmbiguous() {
        let dup = Self.sample + "\n" +
            "/tc/usr/bin/swiftc -module-name App -target wasm32-unknown-wasip1 -c /work/Sources/App/Other.swift -o /work/.build/wasm32-unknown-wasip1/debug/App.build/Other.swift.o"
        #expect(BuildCommandParser.parse(verboseOutput: dup, appModule: "App") == nil)
    }

    @Test("shellSplit handles quoted segments and collapses whitespace")
    func tokenizer() {
        #expect(BuildCommandParser.shellSplit(#"a "b c" d"#) == ["a", "b c", "d"])
        #expect(BuildCommandParser.shellSplit("  x   y  ") == ["x", "y"])
        #expect(BuildCommandParser.shellSplit(#""/p/with space/x" -flag"#) == ["/p/with space/x", "-flag"])
    }
}
```

- [ ] **Step 3: Run to verify it fails**

Run: `swift test --filter BuildCommandParserTests`
Expected: FAIL — `cannot find 'BuildCommandParser' in scope`.

- [ ] **Step 4: Implement the parser + tokenizer**

Append to `Sources/SwiflowCLI/DevServer/CompilerBypass.swift`:

```swift
/// Parses verbose `swift build --product App -v` output into the two commands
/// the bypass replays. Pure and table-free so it's fully unit-testable.
enum BuildCommandParser {

    /// Returns the (compile, link) commands, or nil if either anchor is absent
    /// or the compile job can't be uniquely identified — caller falls back to
    /// a full `swift build`.
    static func parse(verboseOutput: String, appModule: String) -> (compile: ResolvedCommand, link: ResolvedCommand)? {
        let lines = verboseOutput.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)

        // Compile: the swiftc line that compiles the app module's objects for
        // wasm. There can be a separate `-emit-module` job carrying the same
        // `-module-name App … wasm32`; we want the object-emitting (`-c`) one.
        let compileCandidates: [ResolvedCommand] = lines.compactMap { line in
            let argv = shellSplit(line)
            guard argv.first?.hasSuffix("swiftc") == true,
                  hasFlagValue(argv, "-module-name", appModule),
                  argv.contains(where: { $0.contains("wasm32") }),
                  argv.contains("-c")
            else { return nil }
            return ResolvedCommand(executable: URL(fileURLWithPath: argv[0]), arguments: Array(argv.dropFirst()))
        }
        guard compileCandidates.count == 1, let compile = compileCandidates.first else { return nil }

        // Link: the clang driver line whose `-o` output is `App.wasm`. The bare
        // nested `wasm-ld` line is clang's internal spawn — not what we replay.
        let linkCandidates: [ResolvedCommand] = lines.compactMap { line in
            let argv = shellSplit(line)
            guard argv.first?.hasSuffix("clang") == true,
                  let oIndex = argv.firstIndex(of: "-o"),
                  oIndex + 1 < argv.count,
                  argv[oIndex + 1].hasSuffix("/App.wasm")
            else { return nil }
            return ResolvedCommand(executable: URL(fileURLWithPath: argv[0]), arguments: Array(argv.dropFirst()))
        }
        guard linkCandidates.count == 1, let link = linkCandidates.first else { return nil }

        return (compile, link)
    }

    /// True iff `argv` contains `flag` immediately followed by `value`.
    private static func hasFlagValue(_ argv: [String], _ flag: String, _ value: String) -> Bool {
        guard let i = argv.firstIndex(of: flag), i + 1 < argv.count else { return false }
        return argv[i + 1] == value
    }

    /// Minimal shell tokenizer: splits on whitespace, honoring double- and
    /// single-quoted segments (quotes are stripped). Sufficient for the argv
    /// SwiftPM prints (quoted paths-with-spaces); no escape/var expansion.
    static func shellSplit(_ line: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character? = nil
        var inToken = false
        for ch in line {
            if let q = quote {
                if ch == q { quote = nil } else { current.append(ch) }
            } else if ch == "\"" || ch == "'" {
                quote = ch; inToken = true
            } else if ch == " " || ch == "\t" {
                if inToken { tokens.append(current); current = ""; inToken = false }
            } else {
                current.append(ch); inToken = true
            }
        }
        if inToken { tokens.append(current) }
        return tokens
    }
}
```

- [ ] **Step 5: Run to verify it passes**

Run: `swift test --filter BuildCommandParserTests`
Expected: PASS (all 5). If `picksCompileJob` fails on the quoted `-I`, confirm `shellSplit` strips quotes; if `nilWhenAmbiguous` fails, confirm the `compileCandidates.count == 1` guard.

- [ ] **Step 6: Ensure the fixture is bundled as a test resource**

The fixture is read via `#filePath`-relative path (not a bundle resource), so no `Package.swift` change is needed — confirm by running the suite. If `Self.sample` is empty, re-check the path math in the test (`Fixtures/swift-build-verbose-sample.txt` sits two levels up from the `DevServer` test dir).

- [ ] **Step 7: Commit**

```bash
git add Sources/SwiflowCLI/DevServer/CompilerBypass.swift Tests/SwiflowCLITests/DevServer/CompilerBypassTests.swift Tests/SwiflowCLITests/Fixtures/swift-build-verbose-sample.txt
git commit -m "feat(cli): BuildCommandParser — extract the -c swiftc + clang link commands from verbose output"
```

---

## Task 4: `StalenessKey`

The "safe to replay?" key: app `.swift` file set + import-line hash + `Package.swift`/`Package.resolved` mtimes. Equal key ⇒ replay; any diff ⇒ re-capture.

**Files:**
- Modify: `Sources/SwiflowCLI/DevServer/CompilerBypass.swift`
- Test: `Tests/SwiflowCLITests/DevServer/CompilerBypassTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `Tests/SwiflowCLITests/DevServer/CompilerBypassTests.swift`:

```swift
@Suite("StalenessKey")
struct StalenessKeyTests {

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("stalekey-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func key(_ srcDir: URL, _ root: URL) -> StalenessKey {
        StalenessKey.compute(
            appSourcesDir: srcDir,
            manifestURL: root.appendingPathComponent("Package.swift"),
            resolvedURL: root.appendingPathComponent("Package.resolved")
        )
    }

    @Test("Stable across a file-body edit")
    func stableAcrossBodyEdit() throws {
        let root = try tempDir(); defer { try? FileManager.default.removeItem(at: root) }
        let src = root.appendingPathComponent("Sources/App")
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        let f = src.appendingPathComponent("App.swift")
        try "import SwiflowWeb\nlet x = 1\n".write(to: f, atomically: true, encoding: .utf8)
        let k1 = key(src, root)
        try "import SwiflowWeb\nlet x = 2 // changed body\n".write(to: f, atomically: true, encoding: .utf8)
        #expect(key(src, root) == k1)
    }

    @Test("sourceSet differs when a file is added")
    func differsOnAddedFile() throws {
        let root = try tempDir(); defer { try? FileManager.default.removeItem(at: root) }
        let src = root.appendingPathComponent("Sources/App")
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        try "let a = 1".write(to: src.appendingPathComponent("A.swift"), atomically: true, encoding: .utf8)
        let k1 = key(src, root)
        try "let b = 2".write(to: src.appendingPathComponent("B.swift"), atomically: true, encoding: .utf8)
        #expect(key(src, root) != k1)
        #expect(key(src, root).sourceSet.count == 2)
    }

    @Test("importHash differs when an import is added (file set unchanged)")
    func differsOnNewImport() throws {
        let root = try tempDir(); defer { try? FileManager.default.removeItem(at: root) }
        let src = root.appendingPathComponent("Sources/App")
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        let f = src.appendingPathComponent("App.swift")
        try "import SwiflowWeb\nlet x = 1\n".write(to: f, atomically: true, encoding: .utf8)
        let k1 = key(src, root)
        try "import SwiflowWeb\nimport SwiflowQuery\nlet x = 1\n".write(to: f, atomically: true, encoding: .utf8)
        let k2 = key(src, root)
        #expect(k2 != k1)
        #expect(k2.sourceSet == k1.sourceSet)   // same files, only imports changed
    }

    @Test("Recurses subdirectories; tolerates a missing Package.resolved")
    func recursesAndToleratesMissingResolved() throws {
        let root = try tempDir(); defer { try? FileManager.default.removeItem(at: root) }
        let src = root.appendingPathComponent("Sources/App")
        let sub = src.appendingPathComponent("Views")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try "let a = 1".write(to: src.appendingPathComponent("App.swift"), atomically: true, encoding: .utf8)
        try "let v = 1".write(to: sub.appendingPathComponent("View.swift"), atomically: true, encoding: .utf8)
        let k = key(src, root)               // no Package.swift / Package.resolved exist
        #expect(k.sourceSet.count == 2)      // recursed into Views/
        #expect(k.resolvedMTime == nil)
        #expect(k.manifestMTime == nil)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter StalenessKeyTests`
Expected: FAIL — `cannot find 'StalenessKey' in scope`.

- [ ] **Step 3: Implement `StalenessKey`**

Append to `Sources/SwiflowCLI/DevServer/CompilerBypass.swift`:

```swift
/// The "is a replay still correct?" key. A replay is safe iff the frozen
/// swiftc/link argv is still the *correct* argv: file-body edits don't change
/// it (swiftc incremental + the stable LinkFileList cover those), but a
/// different source list, import surface, or manifest does. These four fields
/// detect exactly those. Compared in-process within one dev session only
/// (never persisted), so `importHash` may use a per-process hash.
struct StalenessKey: Sendable, Equatable {
    let sourceSet: Set<String>
    let importHash: Int
    let manifestMTime: Date?
    let resolvedMTime: Date?

    static func compute(appSourcesDir: URL, manifestURL: URL, resolvedURL: URL) -> StalenessKey {
        let fm = FileManager.default

        // Walk *.swift under the app sources (recursive).
        var paths: Set<String> = []
        var imports: Set<String> = []
        if let en = fm.enumerator(at: appSourcesDir, includingPropertiesForKeys: nil) {
            for case let url as URL in en where url.pathExtension == "swift" {
                paths.insert(url.standardizedFileURL.path)
                if let text = try? String(contentsOf: url, encoding: .utf8) {
                    for raw in text.split(separator: "\n") {
                        let line = raw.trimmingCharacters(in: .whitespaces)
                        if line.hasPrefix("import ")
                            || line.hasPrefix("@testable import ")
                            || line.hasPrefix("@_exported import ") {
                            imports.insert(line)
                        }
                    }
                }
            }
        }
        let importHash = imports.sorted().joined(separator: "\n").hashValue

        return StalenessKey(
            sourceSet: paths,
            importHash: importHash,
            manifestMTime: Self.mtime(manifestURL, fm),
            resolvedMTime: Self.mtime(resolvedURL, fm)
        )
    }

    private static func mtime(_ url: URL, _ fm: FileManager) -> Date? {
        (try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter StalenessKeyTests`
Expected: PASS (all 4).

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiflowCLI/DevServer/CompilerBypass.swift Tests/SwiflowCLITests/DevServer/CompilerBypassTests.swift
git commit -m "feat(cli): StalenessKey — file set + import hash + manifest mtimes drive replay-vs-recapture"
```

---

## Task 5: `CapturedBuildCommands` + `CommandReplayer`

Bundle the two commands with the key they were captured against, and run them in order (compile → link), streaming output, throwing on any non-zero exit.

**Files:**
- Modify: `Sources/SwiflowCLI/DevServer/CompilerBypass.swift`
- Test: `Tests/SwiflowCLITests/DevServer/CompilerBypassTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `Tests/SwiflowCLITests/DevServer/CompilerBypassTests.swift`:

```swift
@Suite("CommandReplayer")
struct CommandReplayerTests {

    private func sampleCommands() -> CapturedBuildCommands {
        CapturedBuildCommands(
            compile: ResolvedCommand(executable: URL(fileURLWithPath: "/tc/swiftc"), arguments: ["-c", "App.swift"]),
            link: ResolvedCommand(executable: URL(fileURLWithPath: "/tc/clang"), arguments: ["-o", "App.wasm"]),
            key: StalenessKey(sourceSet: [], importHash: 0, manifestMTime: nil, resolvedMTime: nil)
        )
    }

    @Test("Runs compile then link, in order, from the working directory")
    func runsBothInOrder() throws {
        let stub = StubProcessRunner(stubbedExitCode: 0)
        try CommandReplayer.replay(sampleCommands(), using: stub, workingDirectory: URL(fileURLWithPath: "/proj"))
        #expect(stub.calls.count == 2)
        #expect(stub.calls[0].executable.path == "/tc/swiftc")
        #expect(stub.calls[0].arguments == ["-c", "App.swift"])
        #expect(stub.calls[1].executable.path == "/tc/clang")
        #expect(stub.calls[1].arguments == ["-o", "App.wasm"])
        #expect(stub.calls[0].workingDirectory?.path == "/proj")
    }

    @Test("A non-zero compile exit throws and link does NOT run")
    func compileFailureStopsBeforeLink() {
        let stub = StubProcessRunner(stubbedExitCode: 4)   // first call (compile) fails
        #expect(throws: BuildCommandError.swiftBuildFailed(exitCode: 4)) {
            try CommandReplayer.replay(sampleCommands(), using: stub, workingDirectory: URL(fileURLWithPath: "/proj"))
        }
        #expect(stub.calls.count == 1)   // link never attempted
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter CommandReplayerTests`
Expected: FAIL — `cannot find 'CapturedBuildCommands' / 'CommandReplayer' in scope`.

- [ ] **Step 3: Implement both**

Append to `Sources/SwiflowCLI/DevServer/CompilerBypass.swift`:

```swift
/// The two replayable commands plus the staleness key they were captured under.
struct CapturedBuildCommands: Sendable, Equatable {
    let compile: ResolvedCommand
    let link: ResolvedCommand
    let key: StalenessKey
}

/// Runs the captured compile then link, streaming output to the user
/// (captureOutput: false). A non-zero exit throws `swiftBuildFailed` — for a
/// real compile error that surfaces the diagnostics and the dev loop skips the
/// HMR broadcast, exactly like today's failed rebuild. Stale-replay "no such
/// module" cases are prevented up front by StalenessKey's importHash, so we do
/// NOT auto-recapture on failure (that would make every mid-edit compile error
/// pay a ~12s rebuild — fast failure feedback is worth more).
enum CommandReplayer {
    static func replay(_ commands: CapturedBuildCommands, using runner: ProcessRunner, workingDirectory: URL) throws {
        for command in [commands.compile, commands.link] {
            let result = try runner.run(
                executable: command.executable,
                arguments: command.arguments,
                workingDirectory: workingDirectory,
                environment: nil,
                captureOutput: false
            )
            if result.exitCode != 0 {
                throw BuildCommandError.swiftBuildFailed(exitCode: result.exitCode)
            }
        }
    }
}
```

> Note: the captured argv carries absolute paths, so the environment doesn't need `TOOLCHAINS` (the toolchain is already baked into the executable paths SwiftPM emitted). `workingDirectory` is the package root, matching how SwiftPM ran them.

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter CommandReplayerTests`
Expected: PASS (both).

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiflowCLI/DevServer/CompilerBypass.swift Tests/SwiflowCLITests/DevServer/CompilerBypassTests.swift
git commit -m "feat(cli): CapturedBuildCommands + CommandReplayer (compile then link, throw on non-zero)"
```

---

## Task 6: `BypassState` + `BypassRebuilder` (orchestrator)

The decision engine: replay when the key matches, else capture-build + re-key, with a latched fallback on parse failure. Always copies the fresh wasm over the served output afterward (replay/capture both write `artifactURL`).

**Files:**
- Modify: `Sources/SwiflowCLI/DevServer/CompilerBypass.swift`
- Test: `Tests/SwiflowCLITests/DevServer/CompilerBypassTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `Tests/SwiflowCLITests/DevServer/CompilerBypassTests.swift`:

```swift
@Suite("BypassRebuilder decision logic")
struct BypassRebuilderTests {

    // Builds a temp project (Sources/App + Package.swift), a fake raw-build
    // artifact, and a stale served wasm. Returns the rebuilder + temp root.
    private func fixture(sample: String) throws -> (BypassRebuilder, URL, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("bypass-\(UUID().uuidString)")
        let src = root.appendingPathComponent("Sources/App")
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        try "import SwiflowWeb\nlet x = 1\n".write(to: src.appendingPathComponent("App.swift"), atomically: true, encoding: .utf8)
        try "// pkg".write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)

        let artifact = root.appendingPathComponent("App.wasm")           // "raw build output"
        try Data([0x00, 0x61, 0x73, 0x6D]).write(to: artifact)
        let served = root.appendingPathComponent("served.wasm")
        try Data([0xDE, 0xAD]).write(to: served)                         // stale

        let rebuilder = BypassRebuilder(
            capturingBuild: CapturingWasmBuildInvocation(
                swiftExecutable: URL(fileURLWithPath: "/usr/bin/swift"),
                projectPath: root, swiftSDK: "sdk", toolchainBundleID: nil
            ),
            fallback: RawWasmBuildInvocation(
                swiftExecutable: URL(fileURLWithPath: "/usr/bin/swift"),
                projectPath: root, swiftSDK: "sdk", toolchainBundleID: nil
            ),
            appModule: "App",
            projectPath: root,
            appSourcesDir: src,
            manifestURL: root.appendingPathComponent("Package.swift"),
            resolvedURL: root.appendingPathComponent("Package.resolved"),
            artifactURL: artifact,
            outputWasmURL: served
        )
        return (rebuilder, root, served)
    }

    @Test("First save: runs the capturing -v build, captures, copies the wasm")
    func firstSaveCaptures() throws {
        let (rebuilder, root, served) = try fixture(sample: BuildCommandParserTests.sample)
        defer { try? FileManager.default.removeItem(at: root) }
        let stub = StubProcessRunner(stubbedExitCode: 0, stubbedStandardOutput: BuildCommandParserTests.sample, stubbedStandardError: nil)
        var state = BypassState()

        try rebuilder.rebuild(using: stub, state: &state)

        #expect(stub.calls.count == 1)
        #expect(stub.calls[0].arguments.contains("-v"))         // the capturing build
        #expect(state.captured != nil)                          // commands captured
        #expect(state.bypassDisabled == false)
        #expect(try Data(contentsOf: served) == Data([0x00, 0x61, 0x73, 0x6D]))  // copied
    }

    @Test("Second save, key unchanged: replays (no swift build)")
    func secondSaveReplays() throws {
        let (rebuilder, root, _) = try fixture(sample: BuildCommandParserTests.sample)
        defer { try? FileManager.default.removeItem(at: root) }
        let stub = StubProcessRunner(stubbedExitCode: 0, stubbedStandardOutput: BuildCommandParserTests.sample, stubbedStandardError: nil)
        var state = BypassState()

        try rebuilder.rebuild(using: stub, state: &state)       // capture (1 call: swift build -v)
        try rebuilder.rebuild(using: stub, state: &state)       // replay (2 calls: swiftc, clang)

        #expect(stub.calls.count == 3)
        #expect(stub.calls[1].executable.path.hasSuffix("swiftc"))
        #expect(stub.calls[2].executable.path.hasSuffix("clang"))
        // Neither replay call is a `swift build`.
        #expect(stub.calls[1].arguments.first != "build")
        #expect(stub.calls[2].arguments.first != "build")
    }

    @Test("Source-set change re-captures (runs -v build again)")
    func fileSetChangeRecaptures() throws {
        let (rebuilder, root, _) = try fixture(sample: BuildCommandParserTests.sample)
        defer { try? FileManager.default.removeItem(at: root) }
        let stub = StubProcessRunner(stubbedExitCode: 0, stubbedStandardOutput: BuildCommandParserTests.sample, stubbedStandardError: nil)
        var state = BypassState()

        try rebuilder.rebuild(using: stub, state: &state)       // capture
        // Add a file → sourceSet differs.
        try "let y = 2".write(to: root.appendingPathComponent("Sources/App/B.swift"), atomically: true, encoding: .utf8)
        try rebuilder.rebuild(using: stub, state: &state)       // must re-capture, not replay

        #expect(stub.calls.count == 2)                          // 2 capturing builds, no replay
        #expect(stub.calls[1].arguments.contains("-v"))
    }

    @Test("Parse failure latches bypassDisabled; next save runs the fallback")
    func parseFailureLatchesFallback() throws {
        let (rebuilder, root, _) = try fixture(sample: "garbage with no swiftc or clang lines")
        defer { try? FileManager.default.removeItem(at: root) }
        let stub = StubProcessRunner(stubbedExitCode: 0, stubbedStandardOutput: "garbage with no swiftc or clang lines", stubbedStandardError: nil)
        var state = BypassState()

        try rebuilder.rebuild(using: stub, state: &state)       // capture build runs, parse fails
        #expect(state.bypassDisabled == true)
        #expect(stub.calls.count == 1)

        try rebuilder.rebuild(using: stub, state: &state)       // now uses fallback (plain swift build)
        #expect(stub.calls.count == 2)
        #expect(stub.calls[1].arguments == ["build", "--swift-sdk", "sdk", "--product", "App"])  // RawWasmBuildInvocation argv
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter BypassRebuilderTests`
Expected: FAIL — `cannot find 'BypassState' / 'BypassRebuilder' in scope`.

- [ ] **Step 3: Implement `BypassState` + `BypassRebuilder`**

Append to `Sources/SwiflowCLI/DevServer/CompilerBypass.swift`:

```swift
/// Loop-owned, single-task state. One value keeps the `rebuild` signature
/// stable as the staleness key grows.
struct BypassState: Sendable {
    var captured: CapturedBuildCommands?
    var bypassDisabled: Bool = false
}

/// Orchestrates one save: decide replay-vs-capture, run it, copy the fresh wasm
/// over the served output. Stays a Sendable value type; the non-Sendable
/// ProcessRunner and the mutable `state` are passed per call (the watcher loop
/// owns `state` and runs serially, so there's no cross-task sharing).
struct BypassRebuilder: Sendable {
    let capturingBuild: CapturingWasmBuildInvocation
    let fallback: RawWasmBuildInvocation
    let appModule: String
    let projectPath: URL
    let appSourcesDir: URL
    let manifestURL: URL
    let resolvedURL: URL
    let artifactURL: URL
    let outputWasmURL: URL

    func rebuild(using runner: ProcessRunner, state: inout BypassState) throws {
        // Permanent fallback once capture has proven unparseable this session.
        if state.bypassDisabled {
            try fallback.run(using: runner)
            try WasmArtifactCopier.copy(from: artifactURL, to: outputWasmURL)
            return
        }

        let key = StalenessKey.compute(appSourcesDir: appSourcesDir, manifestURL: manifestURL, resolvedURL: resolvedURL)

        if let captured = state.captured, captured.key == key {
            try CommandReplayer.replay(captured, using: runner, workingDirectory: projectPath)
        } else {
            print(captureReason(old: state.captured?.key, new: key))
            let output = try capturingBuild.run(using: runner)
            if let cmds = BuildCommandParser.parse(verboseOutput: output, appModule: appModule) {
                state.captured = CapturedBuildCommands(compile: cmds.compile, link: cmds.link, key: key)
            } else {
                state.bypassDisabled = true
                print("swiflow: could not capture compile commands; using full builds this session.")
            }
        }

        // Both branches wrote `artifactURL`; publish it to the served output.
        try WasmArtifactCopier.copy(from: artifactURL, to: outputWasmURL)
    }

    /// Human-readable reason for a (re)capture, for the dev console.
    private func captureReason(old: StalenessKey?, new: StalenessKey) -> String {
        guard let old else { return "swiflow: capturing compile commands (one-time)…" }
        if old.sourceSet != new.sourceSet { return "swiflow: app file set changed — re-capturing…" }
        if old.importHash != new.importHash { return "swiflow: imports changed — re-capturing…" }
        return "swiflow: Package.swift changed — re-capturing… (if you added/changed a dependency, restart swiflow dev)"
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter BypassRebuilderTests`
Expected: PASS (all 4). The `print(...)` lines write to the test console — harmless.

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiflowCLI/DevServer/CompilerBypass.swift Tests/SwiflowCLITests/DevServer/CompilerBypassTests.swift
git commit -m "feat(cli): BypassRebuilder — replay-or-recapture decision engine with latched fallback"
```

---

## Task 7: Wire `BypassRebuilder` into `DevCommand`

Replace the `FastRebuilder` construction and the watcher-loop branch with `BypassRebuilder` + loop-owned `var state: BypassState`.

**Files:**
- Modify: `Sources/SwiflowCLI/Commands/DevCommand.swift` (the `4.5` rebuilder setup ~lines 106-134 and the watcher `group.addTask` body ~lines 160-179)

- [ ] **Step 1: Replace the rebuilder construction (was `fastRebuilder`)**

In `Sources/SwiflowCLI/Commands/DevCommand.swift`, replace the block that builds `let fastRebuilder: FastRebuilder? = WasmArtifactLocator.resolve(...).map { ... }` and its `if fastRebuilder == nil { ... }` notice with:

```swift
        // 4.5 Build the bypass rebuilder. The dev loop replays SwiftPM's own
        //     swiftc + wasm-ld commands per save (~1.6s), re-capturing them via
        //     a full `swift build` whenever the app source/import set or the
        //     manifest changes. If the wasm bin path can't be resolved we leave
        //     it nil and fall back to the full `swift package js` per save.
        let outputWasmURL = projectURL
            .appendingPathComponent(Self.packageToJSOutputRelativePath)
            .appendingPathComponent("App.wasm")
        let bypassRebuilder: BypassRebuilder? = WasmArtifactLocator.resolve(
            swiftExecutable: swift,
            projectPath: projectURL,
            swiftSDK: sdk,
            toolchainBundleID: toolchainBundleID,
            using: runner
        ).map { artifactURL in
            BypassRebuilder(
                capturingBuild: CapturingWasmBuildInvocation(
                    swiftExecutable: swift,
                    projectPath: projectURL,
                    swiftSDK: sdk,
                    toolchainBundleID: toolchainBundleID
                ),
                fallback: RawWasmBuildInvocation(
                    swiftExecutable: swift,
                    projectPath: projectURL,
                    swiftSDK: sdk,
                    toolchainBundleID: toolchainBundleID
                ),
                appModule: "App",
                projectPath: projectURL,
                appSourcesDir: projectURL.appendingPathComponent("Sources/App"),
                manifestURL: projectURL.appendingPathComponent("Package.swift"),
                resolvedURL: projectURL.appendingPathComponent("Package.resolved"),
                artifactURL: artifactURL,
                outputWasmURL: outputWasmURL
            )
        }
        if bypassRebuilder == nil {
            print("swiflow: fast rebuild unavailable (could not resolve the wasm bin path); using full packaging per save.")
        }
```

- [ ] **Step 2: Replace the watcher-loop rebuild branch**

In the `group.addTask { ... }` watcher pump, replace the `let rebuildRunner = SystemProcessRunner()` + `for await changed ...` body so it owns `var state` and calls the bypass:

```swift
            group.addTask {
                // ProcessRunner is intentionally non-Sendable; this task gets
                // its own stateless runner. `state` persists across saves and
                // is owned solely by this serial loop (no cross-task sharing) —
                // do NOT parallelize this loop (it would corrupt shared swiftc
                // incremental state in .build).
                let rebuildRunner = SystemProcessRunner()
                var state = BypassState()
                for await changed in watcher.changes() {
                    print("swiflow: rebuilding (\(changed.count) file\(changed.count == 1 ? "" : "s") changed)...")
                    do {
                        if let bypassRebuilder {
                            try bypassRebuilder.rebuild(using: rebuildRunner, state: &state)
                        } else {
                            _ = try invocation.run(using: rebuildRunner)
                        }
                        let bust = Self.wasmCacheBusterSuffix(projectURL: projectURL)
                        await server.hub.broadcastHMRSwap(
                            wasmURL: "/\(Self.packageToJSOutputRelativePath)/App.wasm?h=\(bust)",
                            jsURL: "/\(Self.packageToJSOutputRelativePath)/index.js?h=\(bust)"
                        )
                        print("swiflow: HMR broadcast")
                    } catch {
                        print("swiflow: rebuild failed — \(error). Browser unchanged; fix and save to retry.")
                    }
                }
            }
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: `Build complete!` (ignore the benign `DecodingError` macro-plugin noise). No reference to the removed `fastRebuilder` remains.

- [ ] **Step 4: Run the full CLI suite to confirm no regression**

Run: `swift test --filter SwiflowCLITests`
Expected: pass (the `FastRebuilder*` unit suites still pass — those types are untouched; `BypassRebuilderTests` etc. pass). Re-run `OnChangeStorageTests` in isolation if it flakes.

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiflowCLI/Commands/DevCommand.swift
git commit -m "feat(cli): wire BypassRebuilder into swiflow dev (replace FastRebuilder in the watch loop)"
```

---

## Task 8: Gated end-to-end integration test

Prove the real loop: capture → replay → re-capture-on-new-file → replay, with the served wasm reflecting each edit, and the replay path actually replaying (not building).

**Files:**
- Modify: `Tests/SwiflowCLITests/DevServer/CompilerBypassTests.swift`

- [ ] **Step 1: Write the gated integration test (with a recording runner)**

Append to `Tests/SwiflowCLITests/DevServer/CompilerBypassTests.swift`:

```swift
// MARK: - End-to-end (gated on WASM SDK presence)

/// Wraps a real runner, recording every call's argv while executing for real.
/// Lets the test assert which path (build vs replay) ran.
final class RecordingProcessRunner: ProcessRunner {
    let inner = SystemProcessRunner()
    private(set) var calls: [[String]] = []
    func run(executable: URL, arguments: [String], workingDirectory: URL?, environment: [String: String]?, captureOutput: Bool) throws -> ProcessResult {
        calls.append([executable.lastPathComponent] + arguments)
        return try inner.run(executable: executable, arguments: arguments, workingDirectory: workingDirectory, environment: environment, captureOutput: captureOutput)
    }
}

@Suite("BypassRebuilder end-to-end (requires WASM SDK)")
struct BypassRebuilderIntegrationTests {

    static var wasmSDKAvailable: Bool {
        let runner = SystemProcessRunner()
        let result = try? runner.run(
            executable: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["swift", "sdk", "list"],
            workingDirectory: nil, environment: nil, captureOutput: true
        )
        guard let stdout = result?.standardOutput else { return false }
        return !WasmSDKProbe.parseSDKList(stdout).isEmpty
    }

    static var swiflowRepoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // DevServer
            .deletingLastPathComponent()   // SwiflowCLITests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
    }

    @Test("capture → replay → recapture-on-new-file → replay; served wasm tracks each edit",
          .enabled(if: wasmSDKAvailable), .timeLimit(.minutes(5)))
    func realBypassLoop() async throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("swiflow-bypass-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        // 1. Scaffold HelloWorld pointing at this checkout.
        try ProjectWriter.writeProject(
            name: "Demo",
            template: EmbeddedTemplates.lookup("HelloWorld")!,
            into: tmp,
            swiflowDep: .path(Self.swiflowRepoRoot.path),
            jsDriverSource: EmbeddedDriver.javascriptSource,
            jsServiceWorkerSource: EmbeddedDriver.serviceWorkerSource
        )
        let projectPath = tmp.appendingPathComponent("Demo")
        let appSwift = projectPath.appendingPathComponent("Sources/App/App.swift")

        // 2. Probe swift + SDK + toolchain.
        let probeRunner = SystemProcessRunner()
        guard let swift = try SwiftExecutableLocator.locate(using: probeRunner) else { Issue.record("swift not on PATH"); return }
        guard let sdk = try WasmSDKProbe(runner: probeRunner, swiftExecutable: swift).list().first else { Issue.record("no SDK"); return }
        let toolchainBundleID = MacToolchainProbe.swiftLatestBundleIdentifier()

        // 3. Initial full build (produces the served glue + first wasm).
        let initial = BuildInvocation(swiftExecutable: swift, projectPath: projectPath, swiftSDK: sdk, toolchainBundleID: toolchainBundleID, configuration: .dev)
        #expect(try initial.run(using: probeRunner).exitCode == 0)

        let outputWasmURL = projectPath.appendingPathComponent(DevCommand.packageToJSOutputRelativePath).appendingPathComponent("App.wasm")
        let artifactURL = try #require(WasmArtifactLocator.resolve(swiftExecutable: swift, projectPath: projectPath, swiftSDK: sdk, toolchainBundleID: toolchainBundleID, using: probeRunner))

        let rebuilder = BypassRebuilder(
            capturingBuild: CapturingWasmBuildInvocation(swiftExecutable: swift, projectPath: projectPath, swiftSDK: sdk, toolchainBundleID: toolchainBundleID),
            fallback: RawWasmBuildInvocation(swiftExecutable: swift, projectPath: projectPath, swiftSDK: sdk, toolchainBundleID: toolchainBundleID),
            appModule: "App", projectPath: projectPath,
            appSourcesDir: projectPath.appendingPathComponent("Sources/App"),
            manifestURL: projectPath.appendingPathComponent("Package.swift"),
            resolvedURL: projectPath.appendingPathComponent("Package.resolved"),
            artifactURL: artifactURL, outputWasmURL: outputWasmURL
        )
        var state = BypassState()
        let runner = RecordingProcessRunner()

        func markerPresent(_ marker: String) throws -> Bool {
            let data = try Data(contentsOf: outputWasmURL)
            return data.range(of: Data(marker.utf8)) != nil
        }
        func injectExportedSymbol(_ name: String) throws {
            var src = try String(contentsOf: appSwift, encoding: .utf8)
            src += "\n@_cdecl(\"\(name)\") public func \(name)() -> Int32 { 0 }\n"
            try src.write(to: appSwift, atomically: true, encoding: .utf8)
        }

        // 4. First save (body edit) → capture. Served wasm gets marker M1.
        try injectExportedSymbol("bypass_marker_one")
        try rebuilder.rebuild(using: runner, state: &state)
        #expect(state.captured != nil)
        #expect(try markerPresent("bypass_marker_one"))
        let callsAfterCapture = runner.calls.count

        // 5. Second save (different body edit) → REPLAY (no swift build).
        try injectExportedSymbol("bypass_marker_two")
        try rebuilder.rebuild(using: runner, state: &state)
        #expect(try markerPresent("bypass_marker_two"))
        let replayCalls = runner.calls[callsAfterCapture...]
        #expect(!replayCalls.contains { $0.first == "swift" && $0.dropFirst().first == "build" })  // replayed, didn't build
        #expect(replayCalls.contains { $0.first?.hasSuffix("swiftc") == true })

        // 6. Add a NEW file with a function and REFERENCE it from App.swift via
        //    an exported symbol → sourceSet changes → re-capture must compile the
        //    new file, else the link fails on the undefined reference (a stronger
        //    check than relying on a dead-strippable unreferenced export).
        let newFile = projectPath.appendingPathComponent("Sources/App/Extra.swift")
        try "func extraValue() -> Int32 { 31337 }\n".write(to: newFile, atomically: true, encoding: .utf8)
        var withRef = try String(contentsOf: appSwift, encoding: .utf8)
        withRef += "\n@_cdecl(\"bypass_marker_three\") public func m3() -> Int32 { extraValue() }\n"
        try withRef.write(to: appSwift, atomically: true, encoding: .utf8)
        try rebuilder.rebuild(using: runner, state: &state)        // re-capture compiles Extra.swift
        #expect(try markerPresent("bypass_marker_three"))

        // 7. A further body edit after the re-capture must REPLAY correctly,
        //    proving the shared .build incremental state stays coherent across
        //    the replay → capture → replay alternation.
        try injectExportedSymbol("bypass_marker_four")
        try rebuilder.rebuild(using: runner, state: &state)        // replay after recapture
        #expect(try markerPresent("bypass_marker_four"))
        #expect(try markerPresent("bypass_marker_three"))          // earlier symbol still linked in
    }
}
```

- [ ] **Step 2: Run the gated integration test**

Run: `swift test --filter BypassRebuilderIntegrationTests`
Expected: PASS when a WASM SDK is installed (~1–3 min). If no SDK, it's skipped (the `.enabled(if:)` gate) — that's acceptable, but try to run it on a machine with the SDK before merge.

- [ ] **Step 3: Full suite + build**

Run: `swift build && swift test --filter SwiflowCLITests`
Expected: builds; all suites pass (re-run `OnChangeStorageTests` in isolation if it flakes — known ~1/3 parallel flake, not a regression).

- [ ] **Step 4: Commit**

```bash
git add Tests/SwiflowCLITests/DevServer/CompilerBypassTests.swift
git commit -m "test(cli): gated e2e — capture→replay→recapture→replay loop tracks each edit in the served wasm"
```

---

## Final verification (after all tasks)

- [ ] `swift build` → `Build complete!`
- [ ] `swift test --filter SwiflowCLITests` → green (modulo the known `OnChangeStorageTests` parallel flake; confirm in isolation)
- [ ] Manual smoke (optional, on a machine with the WASM SDK): in a scratch HelloWorld project, `swift run swiflow dev`, edit `App.swift`, confirm the first save prints "capturing compile commands (one-time)…", subsequent saves rebuild in ~1–2s and the browser swaps. Add a new `.swift` file and confirm the "app file set changed — re-capturing…" path picks it up.

## Notes for the reviewer

- `FastRebuild.swift` is intentionally untouched (its types are reused). `FastRebuilder` itself is now unused by `DevCommand` but is left in place + tested; removing it is out of scope (a separate cleanup if desired).
- The js-driver / `EmbeddedDriver` are NOT modified — no driver-embedding regen needed.
- No `examples/` changes — no `embed-templates.swift` regen needed.
