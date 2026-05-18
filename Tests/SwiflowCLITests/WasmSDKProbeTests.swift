// Tests/SwiflowCLITests/WasmSDKProbeTests.swift
import Foundation
import Testing
@testable import SwiflowCLI

@Suite("WasmSDKProbe")
struct WasmSDKProbeTests {

    @Test("Picks the first wasm-suffixed SDK from a multi-line listing")
    func picksFirstWasmSDK() {
        let listing = """
        swift-6.3-RELEASE_wasm
        swift-6.3-RELEASE_static-linux-musl
        """
        let result = WasmSDKProbe.parseSDKList(listing)
        #expect(result == ["swift-6.3-RELEASE_wasm"])
    }

    @Test("Returns multiple wasm SDKs when present, in listing order")
    func picksAllWasm() {
        let listing = """
        swift-6.2-RELEASE_wasm
        swift-6.3-RELEASE_wasm
        swift-DEVELOPMENT-SNAPSHOT-2026-04-01_wasm
        """
        let result = WasmSDKProbe.parseSDKList(listing)
        #expect(result == [
            "swift-6.2-RELEASE_wasm",
            "swift-6.3-RELEASE_wasm",
            "swift-DEVELOPMENT-SNAPSHOT-2026-04-01_wasm",
        ])
    }

    @Test("Ignores blank lines and trims whitespace")
    func handlesWhitespace() {
        let listing = """

          swift-6.3-RELEASE_wasm

        """
        let result = WasmSDKProbe.parseSDKList(listing)
        #expect(result == ["swift-6.3-RELEASE_wasm"])
    }

    @Test("Returns empty for a listing with no wasm SDKs")
    func emptyOnNoWasm() {
        let listing = "swift-6.3-RELEASE_static-linux-musl\n"
        let result = WasmSDKProbe.parseSDKList(listing)
        #expect(result.isEmpty)
    }

    @Test("pickDefault returns the FIRST wasm SDK from the parsed list")
    func pickDefaultReturnsFirst() {
        let listing = """
        swift-6.2-RELEASE_wasm
        swift-6.3-RELEASE_wasm
        """
        #expect(WasmSDKProbe.pickDefault(from: listing) == "swift-6.2-RELEASE_wasm")
    }

    @Test("pickDefault returns nil for empty listing")
    func pickDefaultEmpty() {
        #expect(WasmSDKProbe.pickDefault(from: "") == nil)
    }

    @Test("list() shells out via the runner and parses the output")
    func listShellsOut() throws {
        let stub = StubProcessRunner(
            stubbedExitCode: 0,
            stubbedStandardOutput: "swift-6.3-RELEASE_wasm\n"
        )
        let probe = WasmSDKProbe(runner: stub, swiftExecutable: URL(fileURLWithPath: "/usr/bin/swift"))
        let result = try probe.list()
        #expect(result == ["swift-6.3-RELEASE_wasm"])
        #expect(stub.calls.first?.arguments == ["sdk", "list"])
    }

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
}
