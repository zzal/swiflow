// Tests/SwiflowCLITests/BuildCommandTests.swift
import Foundation
import Testing
@testable import SwiflowCLI

@Suite("BuildCommand argv composition")
struct BuildCommandArgvTests {

    @Test("Builds the correct swift package js argv")
    func argvComposition() throws {
        let stub = StubProcessRunner(stubbedExitCode: 0)
        let composer = BuildInvocation(
            swiftExecutable: URL(fileURLWithPath: "/usr/bin/swift"),
            projectPath: URL(fileURLWithPath: "/tmp/demo"),
            swiftSDK: "swift-6.3-RELEASE_wasm",
            toolchainBundleID: nil
        )
        let result = try composer.run(using: stub)
        #expect(result.exitCode == 0)
        #expect(stub.calls.count == 1)
        let call = stub.calls[0]
        #expect(call.executable.path == "/usr/bin/swift")
        #expect(call.arguments == [
            "package",
            "--swift-sdk", "swift-6.3-RELEASE_wasm",
            "js",
            "--use-cdn",
            "--product", "App",
            "-c", "release",
        ])
        #expect(call.workingDirectory?.path == "/tmp/demo")
    }

    @Test("Sets TOOLCHAINS in the child environment when bundleID supplied")
    func sendsToolchainsEnv() throws {
        let stub = StubProcessRunner(stubbedExitCode: 0)
        let composer = BuildInvocation(
            swiftExecutable: URL(fileURLWithPath: "/usr/bin/swift"),
            projectPath: URL(fileURLWithPath: "/tmp/demo"),
            swiftSDK: "swift-6.3-RELEASE_wasm",
            toolchainBundleID: "org.swift.6320250501"
        )
        _ = try composer.run(using: stub)
        #expect(stub.calls[0].environment?["TOOLCHAINS"] == "org.swift.6320250501")
    }

    @Test("Omits TOOLCHAINS from the child environment when bundleID is nil")
    func skipsToolchainsEnv() throws {
        let stub = StubProcessRunner(stubbedExitCode: 0)
        let composer = BuildInvocation(
            swiftExecutable: URL(fileURLWithPath: "/usr/bin/swift"),
            projectPath: URL(fileURLWithPath: "/tmp/demo"),
            swiftSDK: "swift-6.3-RELEASE_wasm",
            toolchainBundleID: nil
        )
        _ = try composer.run(using: stub)
        // No environment override — runner receives nil.
        #expect(stub.calls[0].environment == nil)
    }

    @Test("Surfaces non-zero exit codes via BuildCommandError")
    func nonZeroExit() {
        let stub = StubProcessRunner(stubbedExitCode: 42)
        let composer = BuildInvocation(
            swiftExecutable: URL(fileURLWithPath: "/usr/bin/swift"),
            projectPath: URL(fileURLWithPath: "/tmp/demo"),
            swiftSDK: "swift-6.3-RELEASE_wasm",
            toolchainBundleID: nil
        )
        #expect(throws: BuildCommandError.swiftPackageJSFailed(exitCode: 42)) {
            _ = try composer.run(using: stub)
        }
    }
}
