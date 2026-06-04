# Fast `swiflow dev` Rebuild Loop — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `swiflow dev` rebuild via `swift build` + a wasm copy (reusing the invariant JS glue) instead of re-running the full `swift package js` PackageToJS pipeline every save — removing ~17s per rebuild — then investigate the ~9s macro/swift-syntax build-graph overhead via a gated spike.

**Architecture:** A new dev-only `FastRebuild.swift` unit composes/runs a plain `swift build --product App` (debug, wasm SDK), resolves the raw wasm artifact path via `swift build --show-bin-path`, and atomically copies that wasm over the served `.build/plugins/PackageToJS/outputs/Package/App.wasm`. `DevCommand` keeps the full `swift package js` for the *initial* build (which generates the JS glue once), then drives the fast path on every file change, falling back to the full path if artifact resolution fails. `swiflow build` (release) is untouched.

**Tech Stack:** Swift 6, ArgumentParser, Foundation, Swift Testing (`@Test`/`#expect`/`@Suite`), the existing `ProcessRunner`/`StubProcessRunner` seam.

---

## Spec

Design: `docs/superpowers/specs/2026-06-04-fast-dev-rebuild-loop-design.md`. Read it for the measured diagnosis and the disproven approaches (resolution, CLI split). This plan implements **Lever 1** (Tasks 1–6, the certain win, fully shippable on its own) then **Lever 2** (Task 7 spike, gating Task 8).

## Constraints for implementers

- **Verify with `swift build` / `swift test`, NOT SourceKit/IDE diagnostics** — "No such module" / "cannot find" reminders are frequently stale on this repo.
- **Git: current branch only.** You MAY `git add` / `git commit`. You MUST NOT run `git checkout` / `switch` / `branch` / `stash` / `reset` / `restore` — the working tree is shared and switching strands the controller.
- `OnChangeStorageTests` is a known ~1/3 parallel-run flake (global-static pollution), NOT a regression — re-run in isolation to confirm.
- The CLI is the `SwiflowCLI` target; tests live in `Tests/SwiflowCLITests`. Build/test just the CLI where possible: `swift test --filter SwiflowCLITests` (or a narrower `--filter <SuiteName>`).
- These changes touch **no** `examples/` files, so no `swift scripts/embed-templates.swift` regen is needed.
- Foundation IS available in `SwiflowCLI` (it's a host tool, not a wasm target) — `Data(contentsOf:)`, `FileManager`, `trimmingCharacters(in:)` are all fine here.

## File Structure

- **Create** `Sources/SwiflowCLI/DevServer/FastRebuild.swift` — three small, independently-testable units:
  - `RawWasmBuildInvocation` — argv composer + `run(using:)` for `swift build --swift-sdk <id> --product App` (mirrors `BuildInvocation` but plain-build, no plugin).
  - `WasmArtifactLocator` — `parseBinPath(_:)` (pure) + `resolve(...)` (queries `swift build --show-bin-path`).
  - `WasmArtifactCopier` — `copy(from:to:)` (atomic).
  - `FastRebuilder` — thin coordinator: `rebuild(using:)` = build then copy.
- **Modify** `Sources/SwiflowCLI/Commands/BuildCommand.swift` — add a `BuildCommandError.swiftBuildFailed(exitCode:)` case (the plain build's failure is not a `swift package js` failure).
- **Modify** `Sources/SwiflowCLI/Commands/DevCommand.swift:121-149` — after the initial build, resolve the fast-rebuild paths; rewire the watcher loop to use `FastRebuilder`, with a full-`swift package js` fallback when resolution fails.
- **Create** `Tests/SwiflowCLITests/DevServer/FastRebuildTests.swift` — unit tests (argv, bin-path parse, copy, coordinator) + a gated integration test.
- **Modify** `docs/perf/2026-05-20-hmr-baseline.md` — record the bypass + the glue-reuse limitation.

---

## Task 1: `RawWasmBuildInvocation` + `swiftBuildFailed` error

**Files:**
- Modify: `Sources/SwiflowCLI/Commands/BuildCommand.swift` (add error case, ~line 14-47)
- Create: `Sources/SwiflowCLI/DevServer/FastRebuild.swift`
- Test: `Tests/SwiflowCLITests/DevServer/FastRebuildTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/SwiflowCLITests/DevServer/FastRebuildTests.swift`:

```swift
// Tests/SwiflowCLITests/DevServer/FastRebuildTests.swift
import Foundation
import Testing
@testable import SwiflowCLI

@Suite("RawWasmBuildInvocation argv")
struct RawWasmBuildInvocationTests {

    @Test("Composes `swift build --swift-sdk <id> --product App`")
    func argvComposition() throws {
        let stub = StubProcessRunner(stubbedExitCode: 0)
        let inv = RawWasmBuildInvocation(
            swiftExecutable: URL(fileURLWithPath: "/usr/bin/swift"),
            projectPath: URL(fileURLWithPath: "/tmp/demo"),
            swiftSDK: "swift-6.3-RELEASE_wasm",
            toolchainBundleID: nil
        )
        let result = try inv.run(using: stub)
        #expect(result.exitCode == 0)
        #expect(stub.calls.count == 1)
        #expect(stub.calls[0].executable.path == "/usr/bin/swift")
        #expect(stub.calls[0].arguments == [
            "build", "--swift-sdk", "swift-6.3-RELEASE_wasm", "--product", "App",
        ])
        #expect(stub.calls[0].workingDirectory?.path == "/tmp/demo")
    }

    @Test("Sets TOOLCHAINS when a bundleID is supplied; omits it otherwise")
    func toolchainsEnv() throws {
        let withTC = StubProcessRunner(stubbedExitCode: 0)
        _ = try RawWasmBuildInvocation(
            swiftExecutable: URL(fileURLWithPath: "/usr/bin/swift"),
            projectPath: URL(fileURLWithPath: "/tmp/demo"),
            swiftSDK: "swift-6.3-RELEASE_wasm",
            toolchainBundleID: "org.swift.6320250501"
        ).run(using: withTC)
        #expect(withTC.calls[0].environment?["TOOLCHAINS"] == "org.swift.6320250501")

        let noTC = StubProcessRunner(stubbedExitCode: 0)
        _ = try RawWasmBuildInvocation(
            swiftExecutable: URL(fileURLWithPath: "/usr/bin/swift"),
            projectPath: URL(fileURLWithPath: "/tmp/demo"),
            swiftSDK: "swift-6.3-RELEASE_wasm",
            toolchainBundleID: nil
        ).run(using: noTC)
        #expect(noTC.calls[0].environment == nil)
    }

    @Test("Non-zero exit throws swiftBuildFailed with the code")
    func nonZeroExitThrows() {
        let stub = StubProcessRunner(stubbedExitCode: 7)
        let inv = RawWasmBuildInvocation(
            swiftExecutable: URL(fileURLWithPath: "/usr/bin/swift"),
            projectPath: URL(fileURLWithPath: "/tmp/demo"),
            swiftSDK: "swift-6.3-RELEASE_wasm",
            toolchainBundleID: nil
        )
        #expect(throws: BuildCommandError.swiftBuildFailed(exitCode: 7)) {
            _ = try inv.run(using: stub)
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter RawWasmBuildInvocationTests`
Expected: FAIL to compile — `cannot find 'RawWasmBuildInvocation'` and `BuildCommandError` has no `swiftBuildFailed`.

- [ ] **Step 3: Add the error case**

In `Sources/SwiflowCLI/Commands/BuildCommand.swift`, add to `enum BuildCommandError` (after `swiftPackageJSFailed`):

```swift
    case swiftBuildFailed(exitCode: Int32)
```

and in its `description` switch, add:

```swift
        case .swiftBuildFailed(let code):
            return "swift build failed with exit code \(code). See output above."
```

- [ ] **Step 4: Create `FastRebuild.swift` with `RawWasmBuildInvocation`**

Create `Sources/SwiflowCLI/DevServer/FastRebuild.swift`:

```swift
// Sources/SwiflowCLI/DevServer/FastRebuild.swift
//
// Dev-only fast rebuild: produce a fresh wasm with a plain `swift build`
// and copy it over the served PackageToJS output, skipping the full
// `swift package js` packaging pipeline (which reruns all 14 MiniMake tasks
// every save — ~17s of waste). The JS glue is invariant across edits
// (Swiflow apps have an empty wasm-imports set), so reusing it is safe.
// See docs/superpowers/specs/2026-06-04-fast-dev-rebuild-loop-design.md.

import Foundation

/// Composes + runs `swift build --swift-sdk <id> --product App` — a plain
/// debug wasm build, NOT the `swift package js` plugin. Mirrors
/// `BuildInvocation`'s shape (argv composer + ProcessRunner.run) so the argv
/// is unit-testable without spawning a process.
struct RawWasmBuildInvocation {
    let swiftExecutable: URL
    let projectPath: URL
    let swiftSDK: String
    let toolchainBundleID: String?

    func composeArguments() -> [String] {
        ["build", "--swift-sdk", swiftSDK, "--product", "App"]
    }

    /// Runs the build, inheriting stdout/stderr (so the user sees progress).
    /// Throws `BuildCommandError.swiftBuildFailed` on a non-zero exit.
    @discardableResult
    func run(using runner: ProcessRunner) throws -> ProcessResult {
        let environment: [String: String]? = toolchainBundleID.map { ["TOOLCHAINS": $0] }
        let result = try runner.run(
            executable: swiftExecutable,
            arguments: composeArguments(),
            workingDirectory: projectPath,
            environment: environment,
            captureOutput: false
        )
        if result.exitCode != 0 {
            throw BuildCommandError.swiftBuildFailed(exitCode: result.exitCode)
        }
        return result
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter RawWasmBuildInvocationTests`
Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add Sources/SwiflowCLI/DevServer/FastRebuild.swift \
        Sources/SwiflowCLI/Commands/BuildCommand.swift \
        Tests/SwiflowCLITests/DevServer/FastRebuildTests.swift
git commit -m "feat(cli): RawWasmBuildInvocation for dev fast-rebuild (swift build)"
```

---

## Task 2: `WasmArtifactLocator` — resolve the raw wasm path

**Files:**
- Modify: `Sources/SwiflowCLI/DevServer/FastRebuild.swift`
- Test: `Tests/SwiflowCLITests/DevServer/FastRebuildTests.swift`

The raw `swift build` writes `App.wasm` under `.build/<triple>/debug/` (e.g. `wasm32-unknown-wasip1`). Rather than hardcode the triple, resolve it once via `swift build --show-bin-path --swift-sdk <id>` (a query — it does not build), which prints the bin directory to stdout.

- [ ] **Step 1: Write the failing test**

Append to `Tests/SwiflowCLITests/DevServer/FastRebuildTests.swift`:

```swift
@Suite("WasmArtifactLocator")
struct WasmArtifactLocatorTests {

    @Test("parseBinPath takes the last non-empty trimmed line")
    func parseBinPathLastLine() {
        #expect(WasmArtifactLocator.parseBinPath(
            "/tmp/demo/.build/wasm32-unknown-wasip1/debug\n") ==
            "/tmp/demo/.build/wasm32-unknown-wasip1/debug")
        // Tolerate a stray leading warning line + surrounding whitespace.
        #expect(WasmArtifactLocator.parseBinPath(
            "warning: blah\n  /tmp/x/.build/wasm32-unknown-wasip1/debug  \n") ==
            "/tmp/x/.build/wasm32-unknown-wasip1/debug")
    }

    @Test("parseBinPath returns nil for empty/whitespace output")
    func parseBinPathEmpty() {
        #expect(WasmArtifactLocator.parseBinPath("") == nil)
        #expect(WasmArtifactLocator.parseBinPath("  \n\t\n") == nil)
    }

    @Test("resolve queries --show-bin-path and appends App.wasm")
    func resolveAppendsAppWasm() {
        let stub = StubProcessRunner(
            stubbedExitCode: 0,
            stubbedStandardOutput: "/tmp/demo/.build/wasm32-unknown-wasip1/debug\n"
        )
        let url = WasmArtifactLocator.resolve(
            swiftExecutable: URL(fileURLWithPath: "/usr/bin/swift"),
            projectPath: URL(fileURLWithPath: "/tmp/demo"),
            swiftSDK: "swift-6.3-RELEASE_wasm",
            toolchainBundleID: nil,
            using: stub
        )
        #expect(url?.path == "/tmp/demo/.build/wasm32-unknown-wasip1/debug/App.wasm")
        #expect(stub.calls[0].arguments == [
            "build", "--show-bin-path", "--swift-sdk", "swift-6.3-RELEASE_wasm",
        ])
        // (capture behavior is implicit: `resolve` only obtains the path from
        // stdout, which ProcessResult populates only when captureOutput == true.)
    }

    @Test("resolve returns nil when the query exits non-zero")
    func resolveNilOnFailure() {
        let stub = StubProcessRunner(stubbedExitCode: 1, stubbedStandardOutput: nil)
        let url = WasmArtifactLocator.resolve(
            swiftExecutable: URL(fileURLWithPath: "/usr/bin/swift"),
            projectPath: URL(fileURLWithPath: "/tmp/demo"),
            swiftSDK: "swift-6.3-RELEASE_wasm",
            toolchainBundleID: nil,
            using: stub
        )
        #expect(url == nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter WasmArtifactLocatorTests`
Expected: FAIL to compile — `cannot find 'WasmArtifactLocator'`.

- [ ] **Step 3: Implement `WasmArtifactLocator`**

Append to `Sources/SwiflowCLI/DevServer/FastRebuild.swift`:

```swift
/// Resolves the raw `swift build` wasm artifact path. The build triple
/// (e.g. `wasm32-unknown-wasip1`) varies by SDK, so we query SwiftPM for the
/// bin directory rather than hardcoding it. `--show-bin-path` is a query: it
/// evaluates the manifest (~1s) but does not build, so it's cheap to run once
/// at dev startup.
enum WasmArtifactLocator {
    /// Parse `--show-bin-path` stdout into the bin directory path. The path is
    /// the only real output; we take the last non-empty trimmed line to be
    /// robust against a stray warning printed before it.
    static func parseBinPath(_ stdout: String) -> String? {
        stdout
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty }
    }

    /// Query the bin path and append `App.wasm`. Returns nil on any failure —
    /// the caller falls back to the full `swift package js` path.
    static func resolve(
        swiftExecutable: URL,
        projectPath: URL,
        swiftSDK: String,
        toolchainBundleID: String?,
        using runner: ProcessRunner
    ) -> URL? {
        let environment: [String: String]? = toolchainBundleID.map { ["TOOLCHAINS": $0] }
        guard
            let result = try? runner.run(
                executable: swiftExecutable,
                arguments: ["build", "--show-bin-path", "--swift-sdk", swiftSDK],
                workingDirectory: projectPath,
                environment: environment,
                captureOutput: true
            ),
            result.exitCode == 0,
            let stdout = result.standardOutput,
            let binPath = parseBinPath(stdout)
        else {
            return nil
        }
        return URL(fileURLWithPath: binPath).appendingPathComponent("App.wasm")
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter WasmArtifactLocatorTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiflowCLI/DevServer/FastRebuild.swift \
        Tests/SwiflowCLITests/DevServer/FastRebuildTests.swift
git commit -m "feat(cli): WasmArtifactLocator resolves raw swift build wasm path"
```

---

## Task 3: `WasmArtifactCopier` — atomic wasm copy

**Files:**
- Modify: `Sources/SwiflowCLI/DevServer/FastRebuild.swift`
- Test: `Tests/SwiflowCLITests/DevServer/FastRebuildTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `Tests/SwiflowCLITests/DevServer/FastRebuildTests.swift`:

```swift
@Suite("WasmArtifactCopier")
struct WasmArtifactCopierTests {

    @Test("copy replaces dest with source bytes (atomic), overwriting prior content")
    func copyOverwrites() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("wasmcopy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let source = dir.appendingPathComponent("src.wasm")
        let dest = dir.appendingPathComponent("dest.wasm")
        try Data([0x00, 0x61, 0x73, 0x6D]).write(to: source) // \0asm magic
        try Data([0xFF, 0xFF]).write(to: dest)               // stale content

        try WasmArtifactCopier.copy(from: source, to: dest)

        #expect(try Data(contentsOf: dest) == Data([0x00, 0x61, 0x73, 0x6D]))
    }

    @Test("copy throws when the source does not exist")
    func copyMissingSourceThrows() {
        let dir = FileManager.default.temporaryDirectory
        let source = dir.appendingPathComponent("does-not-exist-\(UUID().uuidString).wasm")
        let dest = dir.appendingPathComponent("dest-\(UUID().uuidString).wasm")
        #expect(throws: (any Error).self) {
            try WasmArtifactCopier.copy(from: source, to: dest)
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter WasmArtifactCopierTests`
Expected: FAIL to compile — `cannot find 'WasmArtifactCopier'`.

- [ ] **Step 3: Implement `WasmArtifactCopier`**

Append to `Sources/SwiflowCLI/DevServer/FastRebuild.swift`:

```swift
/// Atomically replaces the served wasm with a freshly-built one. Atomic write
/// avoids serving a half-written file if the dev server reads mid-copy.
enum WasmArtifactCopier {
    static func copy(from source: URL, to dest: URL) throws {
        let data = try Data(contentsOf: source)
        try data.write(to: dest, options: .atomic)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter WasmArtifactCopierTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiflowCLI/DevServer/FastRebuild.swift \
        Tests/SwiflowCLITests/DevServer/FastRebuildTests.swift
git commit -m "feat(cli): WasmArtifactCopier atomically replaces served wasm"
```

---

## Task 4: `FastRebuilder` coordinator + gated integration test

**Files:**
- Modify: `Sources/SwiflowCLI/DevServer/FastRebuild.swift`
- Test: `Tests/SwiflowCLITests/DevServer/FastRebuildTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `Tests/SwiflowCLITests/DevServer/FastRebuildTests.swift`:

```swift
@Suite("FastRebuilder")
struct FastRebuilderTests {

    @Test("rebuild() builds then copies the fresh wasm into the served output")
    func rebuildBuildsThenCopies() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("fastrebuild-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // The "raw build output" the stubbed `swift build` pretends to produce.
        let artifact = dir.appendingPathComponent("App.wasm")
        try Data([0x00, 0x61, 0x73, 0x6D, 0x01]).write(to: artifact)
        let served = dir.appendingPathComponent("served-App.wasm")
        try Data([0xDE, 0xAD]).write(to: served) // stale

        let rebuilder = FastRebuilder(
            build: RawWasmBuildInvocation(
                swiftExecutable: URL(fileURLWithPath: "/usr/bin/swift"),
                projectPath: dir,
                swiftSDK: "swift-6.3-RELEASE_wasm",
                toolchainBundleID: nil
            ),
            artifactURL: artifact,
            outputWasmURL: served
        )
        let stub = StubProcessRunner(stubbedExitCode: 0)

        try rebuilder.rebuild(using: stub)

        #expect(stub.calls[0].arguments.contains("build"))      // ran swift build
        #expect(try Data(contentsOf: served) == Data([0x00, 0x61, 0x73, 0x6D, 0x01])) // copied
    }

    @Test("rebuild() throws on build failure and does NOT copy")
    func rebuildThrowsOnBuildFailureNoCopy() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("fastrebuild-fail-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let artifact = dir.appendingPathComponent("App.wasm")
        try Data([0x01]).write(to: artifact)
        let served = dir.appendingPathComponent("served-App.wasm")
        try Data([0xDE, 0xAD]).write(to: served) // must remain untouched

        let rebuilder = FastRebuilder(
            build: RawWasmBuildInvocation(
                swiftExecutable: URL(fileURLWithPath: "/usr/bin/swift"),
                projectPath: dir,
                swiftSDK: "swift-6.3-RELEASE_wasm",
                toolchainBundleID: nil
            ),
            artifactURL: artifact,
            outputWasmURL: served
        )
        let stub = StubProcessRunner(stubbedExitCode: 5)

        #expect(throws: BuildCommandError.swiftBuildFailed(exitCode: 5)) {
            try rebuilder.rebuild(using: stub)
        }
        // Build failed before the copy → served wasm is still the stale bytes.
        #expect(try Data(contentsOf: served) == Data([0xDE, 0xAD]))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter FastRebuilderTests`
Expected: FAIL to compile — `cannot find 'FastRebuilder'`.

- [ ] **Step 3: Implement `FastRebuilder`**

Append to `Sources/SwiflowCLI/DevServer/FastRebuild.swift`:

```swift
/// Coordinates one fast rebuild: build the wasm, then copy it over the served
/// output. Holds the resolved paths so the dev loop just calls `rebuild`.
struct FastRebuilder {
    let build: RawWasmBuildInvocation
    /// Raw `swift build` output, e.g. `.build/wasm32-unknown-wasip1/debug/App.wasm`.
    let artifactURL: URL
    /// Served bundle wasm: `.build/plugins/PackageToJS/outputs/Package/App.wasm`.
    let outputWasmURL: URL

    /// Builds (throws `swiftBuildFailed` on a compile error — the caller then
    /// skips the HMR broadcast, leaving the last good bundle in place), then
    /// copies the fresh wasm into the served output.
    func rebuild(using runner: ProcessRunner) throws {
        try build.run(using: runner)
        try WasmArtifactCopier.copy(from: artifactURL, to: outputWasmURL)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter FastRebuilderTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Add the gated end-to-end integration test**

Append to `Tests/SwiflowCLITests/DevServer/FastRebuildTests.swift`. This proves the *real* `swift build` + copy produces a fresh served wasm — the heart of Lever 1 — using the same init/build path as `BuildCommandIntegrationTests`.

```swift
// MARK: - End-to-end (gated on WASM SDK presence)

@Suite("FastRebuilder end-to-end (requires WASM SDK)")
struct FastRebuilderIntegrationTests {

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

    @Test(
        "real swift build + copy refreshes the served App.wasm",
        .enabled(if: wasmSDKAvailable)
    )
    func realFastRebuild() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiflow-fast-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        // 1. Scaffold a HelloWorld project pointing at this checkout.
        try ProjectWriter.writeProject(
            name: "Demo",
            template: EmbeddedTemplates.lookup("HelloWorld")!,
            into: tmp,
            swiflowDep: .path(Self.swiflowRepoRoot.path),
            jsDriverSource: EmbeddedDriver.javascriptSource,
            jsServiceWorkerSource: EmbeddedDriver.serviceWorkerSource
        )
        let projectPath = tmp.appendingPathComponent("Demo")

        // 2. Probe swift + SDK + toolchain (same path production uses).
        let runner = SystemProcessRunner()
        guard let swift = try SwiftExecutableLocator.locate(using: runner) else {
            Issue.record("swift not on PATH"); return
        }
        let probe = WasmSDKProbe(runner: runner, swiftExecutable: swift)
        guard let sdk = try probe.list().first else {
            Issue.record("no WASM SDK despite gate"); return
        }
        let toolchainBundleID = MacToolchainProbe.swiftLatestBundleIdentifier()

        // 3. Initial full build (generates glue + first wasm in outputs/Package).
        let initial = BuildInvocation(
            swiftExecutable: swift, projectPath: projectPath,
            swiftSDK: sdk, toolchainBundleID: toolchainBundleID, configuration: .dev
        )
        #expect(try initial.run(using: runner).exitCode == 0)

        // 4. Resolve fast-rebuild paths.
        let artifactURL = WasmArtifactLocator.resolve(
            swiftExecutable: swift, projectPath: projectPath,
            swiftSDK: sdk, toolchainBundleID: toolchainBundleID, using: runner
        )
        let resolved = try #require(artifactURL, "should resolve the raw wasm bin path")
        let servedWasm = projectPath
            .appendingPathComponent(DevCommand.packageToJSOutputRelativePath)
            .appendingPathComponent("App.wasm")
        #expect(FileManager.default.fileExists(atPath: servedWasm.path))

        // 5. Mutate a source file so the next build differs, then fast-rebuild.
        let appSwift = projectPath.appendingPathComponent("Sources/App/App.swift")
        var src = try String(contentsOf: appSwift, encoding: .utf8)
        src += "\n// fast-rebuild touch \(UUID().uuidString)\n"
        try src.write(to: appSwift, atomically: true, encoding: .utf8)

        let before = try Data(contentsOf: servedWasm)
        let rebuilder = FastRebuilder(
            build: RawWasmBuildInvocation(
                swiftExecutable: swift, projectPath: projectPath,
                swiftSDK: sdk, toolchainBundleID: toolchainBundleID
            ),
            artifactURL: resolved,
            outputWasmURL: servedWasm
        )
        try rebuilder.rebuild(using: runner)

        // 6. The served wasm is now byte-identical to the freshly-built artifact.
        let after = try Data(contentsOf: servedWasm)
        let artifactBytes = try Data(contentsOf: resolved)
        #expect(after == artifactBytes, "served wasm must equal the fresh build output")
        _ = before // (size may coincide; identity to the artifact is the real check)
    }
}
```

> `#require` is Swift Testing's unwrap-or-fail. If unavailable in the pinned Testing version, replace with `guard let resolved = artifactURL else { Issue.record("…"); return }`.

- [ ] **Step 6: Run the unit suites (and the e2e if a WASM SDK is present)**

Run: `swift test --filter FastRebuild`
Expected: All unit suites PASS. The e2e suite runs only if a WASM SDK is installed (it compiles a real project — minutes); if present, it PASSES.

- [ ] **Step 7: Commit**

```bash
git add Sources/SwiflowCLI/DevServer/FastRebuild.swift \
        Tests/SwiflowCLITests/DevServer/FastRebuildTests.swift
git commit -m "feat(cli): FastRebuilder coordinator + gated e2e (build+copy refreshes wasm)"
```

---

## Task 5: Wire `FastRebuilder` into `DevCommand`

**Files:**
- Modify: `Sources/SwiflowCLI/Commands/DevCommand.swift:106-150`

After the initial build, resolve the fast-rebuild paths once. If resolution succeeds, the watcher loop uses `FastRebuilder` (build + copy + broadcast). If resolution fails, the loop falls back to the existing full `swift package js` path — correct but slow — so the dev server never breaks.

- [ ] **Step 1: Read the current loop**

Read `Sources/SwiflowCLI/Commands/DevCommand.swift:106-150` (the `DevServer` start + `FileWatcher` + `withThrowingTaskGroup` rebuild loop). Confirm:
- `invocation` is the `.dev` `BuildInvocation` used for the initial build (line 92-98).
- the rebuild task already creates its own `rebuildRunner` (line 131).
- `server.hub.broadcastHMRSwap(wasmURL:jsURL:)` + `Self.wasmCacheBusterSuffix` + `Self.packageToJSOutputRelativePath` exist.

- [ ] **Step 2: Resolve fast-rebuild paths after the initial build**

In `DevCommand.run()`, immediately after the initial build succeeds (after line 104, before `let server = DevServer(...)`), add:

```swift
        // Resolve the fast-rebuild paths once. The dev loop rebuilds with a
        // plain `swift build` + a wasm copy (skipping the ~17s PackageToJS
        // repackage), reusing the JS glue the initial build just generated.
        // If resolution fails, `fastRebuilder` stays nil and the loop falls
        // back to the full `swift package js` path (correct, just slow).
        let outputWasmURL = projectURL
            .appendingPathComponent(Self.packageToJSOutputRelativePath)
            .appendingPathComponent("App.wasm")
        let fastRebuilder: FastRebuilder? = WasmArtifactLocator.resolve(
            swiftExecutable: swift,
            projectPath: projectURL,
            swiftSDK: sdk,
            toolchainBundleID: toolchainBundleID,
            using: runner
        ).map { artifactURL in
            FastRebuilder(
                build: RawWasmBuildInvocation(
                    swiftExecutable: swift,
                    projectPath: projectURL,
                    swiftSDK: sdk,
                    toolchainBundleID: toolchainBundleID
                ),
                artifactURL: artifactURL,
                outputWasmURL: outputWasmURL
            )
        }
        if fastRebuilder == nil {
            print("swiflow: fast rebuild unavailable (could not resolve the wasm bin path); using full packaging per save.")
        }
```

> `swift`, `sdk`, `toolchainBundleID`, `projectURL`, and `runner` are all already in scope at this point (lines 38-98).

- [ ] **Step 3: Rewire the watcher loop**

Replace the body of the `for await changed in watcher.changes()` loop (lines 132-145) with:

```swift
                for await changed in watcher.changes() {
                    print("swiflow: rebuilding (\(changed.count) file\(changed.count == 1 ? "" : "s") changed)...")
                    do {
                        if let fastRebuilder {
                            try fastRebuilder.rebuild(using: rebuildRunner)
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
```

> The `fastRebuilder` constant is captured by the `@Sendable` rebuild-task closure. `FastRebuilder` holds only value types (`URL`, `String`) so it's effectively `Sendable`; if the compiler complains, add `Sendable` conformance to `FastRebuilder`, `RawWasmBuildInvocation` (both are structs of `Sendable` members) — do NOT capture `runner`/`rebuildRunner` across the boundary (the loop already creates `rebuildRunner` inside the task).

- [ ] **Step 4: Build the CLI and run the CLI test suite**

Run: `swift build --product swiflow && swift test --filter SwiflowCLITests`
Expected: builds clean; all SwiflowCLITests pass (the existing `DevCommandTests` argv/registration tests still pass; the gated DevCommand e2e still passes if a WASM SDK is present).

- [ ] **Step 5: Manual smoke (only if a WASM SDK + browser are available — otherwise note as deferred)**

```bash
swift build -c release --product swiflow
cd /tmp/Smoke   # or any swiflow project
/path/to/.build/release/swiflow dev --port 3003
```
Open `http://localhost:3003`. Edit `Sources/App/App.swift`, save. Expected: CLI prints `rebuilding…` then `HMR broadcast` **noticeably faster than before** (no `Packaging…`/`[1/14]…` lines), and the browser swaps to the change with `@State` preserved. If no browser is available, confirm from the CLI that the loop no longer prints PackageToJS `Packaging...` lines on each save.

- [ ] **Step 6: Commit**

```bash
git add Sources/SwiflowCLI/Commands/DevCommand.swift
git commit -m "feat(cli): dev loop rebuilds via swift build + wasm copy (skip PackageToJS)"
```

---

## Task 6: Document the bypass + glue-reuse limitation

**Files:**
- Modify: `docs/perf/2026-05-20-hmr-baseline.md`

- [ ] **Step 1: Append a "Dev rebuild loop (2026-06-04)" section**

Add to `docs/perf/2026-05-20-hmr-baseline.md`:

```markdown
## Dev rebuild loop — bypass PackageToJS (2026-06-04)

`swiflow dev` no longer re-runs `swift package js` on every save. The initial
build still runs the full plugin (generating the JS glue + first wasm); each
subsequent save runs a plain `swift build --product App` and copies the fresh
wasm over `.build/plugins/PackageToJS/outputs/Package/App.wasm`, reusing the
glue. This removes the ~17s PackageToJS packaging that reran every save.

**Why glue reuse is safe:** Swiflow apps have an empty wasm-imports set
(`wasm-imports.json` is `[]`) — JavaScriptKit's Swift↔JS bridge is a fixed
runtime ABI, so app-source edits don't change the wasm's imports, and the
generated `index.js`/`instantiate.js`/`runtime.js` glue is invariant across
edits.

**Limitation:** if a project ever changes the low-level JS *import* surface
(not reachable through normal `@Component`/JavaScriptKit usage), the served
glue could go stale. Fix: restart `swiflow dev` (re-runs the full initial
`swift package js`). If resolving the raw wasm bin path fails at startup, the
loop automatically falls back to the full packaging path per save.

**Still in the loop (not addressed here):** ~5–8s compile + WASM relink, ~1s
SwiftPM, and ~9s macro/swift-syntax build-graph stat overhead (Lever 2 spike;
see the design doc).
```

- [ ] **Step 2: Commit**

```bash
git add docs/perf/2026-05-20-hmr-baseline.md
git commit -m "docs(perf): record dev-loop PackageToJS bypass + glue-reuse limitation"
```

---

> **LEVER 1 COMPLETE.** Tasks 1–6 are a self-contained, shippable unit (removes ~17s/save). Run a final whole-feature review here before Lever 2. Lever 2 (Tasks 7–8) is a gated investigation that may produce no code change.

---

## Task 7: Spike A — prebuilt macros (investigation, gated)

**Not TDD — this is a measurement spike.** Goal: determine whether the
`@Component` macro can use the toolchain's prebuilt swift-syntax so an example
stops building/tracking the 234 swift-syntax artifacts that llbuild stats every
no-op build (the measured ~9s).

**Files:**
- Create: `docs/perf/2026-06-04-prebuilt-macros-spike.md` (findings + decision)

- [ ] **Step 1: Capture the baseline**

In a HelloWorld-class project (e.g. `/tmp/Smoke` or a fresh `swiflow init`), after a warm build, record:
```bash
cd <project>
/usr/bin/time -p swift build --swift-sdk swift-6.3-RELEASE_wasm --product App   # no-op wall time
find .build -type f -name "*.o" -path "*wift[Ss]yntax*" | wc -l                 # tracked swift-syntax objects
```
Record both numbers in the findings doc (expected baseline: ~9s, ~234).

- [ ] **Step 2: Investigate prebuilt-macro support**

Research, recording findings in the doc:
- Does the Swift 6.3 toolchain ship a prebuilt swift-syntax for macros? (Check the toolchain's macro/prebuilt directories; check for `SWIFTPM_ENABLE_MACRO_PREBUILTS` / `--enable-prebuilts` style options in `swift build --help` and SwiftPM docs.)
- Does `SwiflowMacrosPlugin` (a `.macro` target on `swift-syntax 600.0.0`) match a version the toolchain provides prebuilt?
- What, concretely, would have to change in the root `Package.swift` / build invocation to use it?

- [ ] **Step 3: Measure with prebuilt enabled (if available)**

If a mechanism exists, enable it for the test project and re-run Step 1's two measurements. Record the new no-op wall time and tracked-artifact count.

- [ ] **Step 4: Record the decision + gate**

Write the conclusion in `docs/perf/2026-06-04-prebuilt-macros-spike.md`:
- **Confirmed** (no-op drops materially, e.g. ≤ ~3s and swift-syntax objects drop toward 0): write a short follow-up plan to fold prebuilt-macros enablement into the project/template + `swiflow dev`. STOP here in this plan; that fold-in is its own task list. Update memory `project_hmr_devloop_diagnosis`.
- **Not feasible / no material gain:** proceed to Task 8.

- [ ] **Step 5: Commit**

```bash
git add docs/perf/2026-06-04-prebuilt-macros-spike.md
git commit -m "docs(perf): prebuilt-macros spike findings + decision"
```

---

## Task 8: Spike B — warm-build feasibility (conditional on Task 7 = not feasible)

**Only if Task 7 concluded prebuilt macros won't help.** Goal: assess whether a
long-lived dev build process can hold llbuild's graph warm so the
234-artifact stat is paid once (at `dev` start) rather than every save.

**Files:**
- Create: `docs/perf/2026-06-04-warm-build-spike.md` (feasibility + recommendation)

- [ ] **Step 1: Investigate the mechanism**

Record findings:
- SwiftPM has no native `--watch`/daemon. Can `libSwiftPM` (the `SwiftPM` library products) load the package graph once and drive repeated incremental builds in-process? What's the API surface / version availability against this toolchain?
- Alternatively, can llbuild be driven directly with a persisted/served build manifest so node signatures aren't recomputed cold each invocation?

- [ ] **Step 2: Prototype just enough to measure**

If an in-process path exists, prototype a minimal harness that loads the graph once and triggers a second no-op build, and measure that second build's wall time vs the ~9s cold-invocation cost. Record the delta.

- [ ] **Step 3: Recommendation + gate**

Write the conclusion in `docs/perf/2026-06-04-warm-build-spike.md`:
- **Viable** (warm no-op materially under ~9s): write a separate implementation plan for a warm dev build (larger effort; out of scope for this plan). Update memory `project_hmr_devloop_diagnosis`.
- **Not viable:** record that Lever 1 (already shipped) is the final state for now; the ~9s macro-graph overhead is a known, toolchain-bound limitation. Update memory.

- [ ] **Step 4: Commit**

```bash
git add docs/perf/2026-06-04-warm-build-spike.md
git commit -m "docs(perf): warm-build feasibility spike + recommendation"
```

---

## Self-review checklist (controller, before dispatching)

- **Spec coverage:** Lever 1 bypass → Tasks 1–5; glue-reuse limitation doc → Task 6; Spike A prebuilt macros → Task 7; Spike B warm-build fallback → Task 8; floor explicitly out of scope (noted in Task 6). ✓
- **Initial build keeps full `swift package js`** (Task 5 leaves line 92-104 untouched; only the loop changes). ✓
- **`swiflow build` untouched** (no task modifies `BuildCommand.run()`'s release path). ✓
- **Fallback path** when bin-path resolution fails (Task 5 Step 2/3). ✓
- **Type consistency:** `RawWasmBuildInvocation`, `WasmArtifactLocator.resolve/parseBinPath`, `WasmArtifactCopier.copy`, `FastRebuilder.rebuild` used identically across Tasks 1–5; `BuildCommandError.swiftBuildFailed(exitCode:)` defined Task 1, used Tasks 1/4. ✓
