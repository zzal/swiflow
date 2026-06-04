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
