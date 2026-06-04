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
