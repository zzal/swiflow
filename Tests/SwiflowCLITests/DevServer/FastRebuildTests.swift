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

        #expect(stub.calls[0].arguments.first == "build")       // ran swift build
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
