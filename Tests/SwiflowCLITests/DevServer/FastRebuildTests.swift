// Tests/SwiflowCLITests/DevServer/FastRebuildTests.swift
import Foundation
import Testing
@testable import SwiflowCLI

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
            context: SwiftContext(
                swift: URL(fileURLWithPath: "/usr/bin/swift"),
                projectPath: URL(fileURLWithPath: "/tmp/demo"),
                sdk: "swift-6.3-RELEASE_wasm",
                toolchainBundleID: nil
            ),
            using: stub
        )
        #expect(url?.path == "/tmp/demo/.build/wasm32-unknown-wasip1/debug/App.wasm")
        #expect(stub.calls[0].arguments == [
            "build", "--show-bin-path", "--swift-sdk", "swift-6.3-RELEASE_wasm",
        ])
        // (capture behavior is implicit: `resolve` only obtains the path from
        // stdout, which ProcessResult populates only when captureOutput == true.)
    }

    // Pin (audit III Wave-2 #10, pre-refactor): the locator's query must run
    // in the PROJECT directory with the TOOLCHAINS env — the same preamble
    // as the builds whose bin path it predicts. A drift here resolves the
    // artifact under a different toolchain than the one that builds it.
    @Test("resolve runs in the project directory with the TOOLCHAINS environment")
    func resolvePreamble() {
        let stub = StubProcessRunner(
            stubbedExitCode: 0,
            stubbedStandardOutput: "/tmp/demo/.build/wasm32-unknown-wasip1/debug\n"
        )
        _ = WasmArtifactLocator.resolve(
            context: SwiftContext(
                swift: URL(fileURLWithPath: "/usr/bin/swift"),
                projectPath: URL(fileURLWithPath: "/tmp/demo"),
                sdk: "swift-6.3-RELEASE_wasm",
                toolchainBundleID: "org.swift.632"
            ),
            using: stub
        )
        #expect(stub.calls[0].workingDirectory?.path == "/tmp/demo")
        #expect(stub.calls[0].environment?["TOOLCHAINS"] == "org.swift.632")
        #expect(stub.calls[0].executable.path == "/usr/bin/swift")
    }

    @Test("resolve returns nil when the query exits non-zero")
    func resolveNilOnFailure() {
        let stub = StubProcessRunner(stubbedExitCode: 1, stubbedStandardOutput: nil)
        let url = WasmArtifactLocator.resolve(
            context: SwiftContext(
                swift: URL(fileURLWithPath: "/usr/bin/swift"),
                projectPath: URL(fileURLWithPath: "/tmp/demo"),
                sdk: "swift-6.3-RELEASE_wasm",
                toolchainBundleID: nil
            ),
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
