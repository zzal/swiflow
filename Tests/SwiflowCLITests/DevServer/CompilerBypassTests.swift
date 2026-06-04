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
