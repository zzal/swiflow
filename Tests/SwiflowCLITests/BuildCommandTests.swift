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

    @Test("BuildCommandError.projectPathNotFound has a useful description")
    func projectPathNotFoundDescription() {
        let url = URL(fileURLWithPath: "/does/not/exist")
        let error = BuildCommandError.projectPathNotFound(url)
        let desc = String(describing: error)
        #expect(desc.contains("does not exist"))
        #expect(desc.contains("/does/not/exist"))
    }

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

    @Test("BuildCommandError.wasmSDKListFailed suppresses trailer when stderr is whitespace-only")
    func wasmSDKListFailedWhitespaceStderr() {
        // The trim+isEmpty check at description time covers a third equivalence
        // class beyond nil and non-empty: stderr that the child captured but
        // that contains nothing actionable (newlines, spaces, tabs). Without
        // trimming, the trailer would render an empty "Details from swift:"
        // block — visual noise with no signal.
        let error = BuildCommandError.wasmSDKListFailed(exitCode: 1, stderr: "   \n\n  \t  ")
        let desc = String(describing: error)
        #expect(desc.contains("exit code 1"))
        #expect(!desc.contains("Details from swift:"))
    }

    @Test("Dev configuration drops -c release and adds --debug-info-format dwarf")
    func devConfigurationArgv() throws {
        let stub = StubProcessRunner(stubbedExitCode: 0)
        let composer = BuildInvocation(
            swiftExecutable: URL(fileURLWithPath: "/usr/bin/swift"),
            projectPath: URL(fileURLWithPath: "/tmp/demo"),
            swiftSDK: "swift-6.3-RELEASE_wasm",
            toolchainBundleID: nil,
            configuration: .dev
        )
        _ = try composer.run(using: stub)
        #expect(stub.calls[0].arguments == [
            "package",
            "--swift-sdk", "swift-6.3-RELEASE_wasm",
            "js",
            "--use-cdn",
            "--product", "App",
            "--debug-info-format", "dwarf",
        ])
    }

    @Test("Release configuration is the default and matches the existing argv")
    func releaseConfigurationIsDefault() throws {
        let stub = StubProcessRunner(stubbedExitCode: 0)
        let composer = BuildInvocation(
            swiftExecutable: URL(fileURLWithPath: "/usr/bin/swift"),
            projectPath: URL(fileURLWithPath: "/tmp/demo"),
            swiftSDK: "swift-6.3-RELEASE_wasm",
            toolchainBundleID: nil
            // configuration omitted — must default to .release
        )
        _ = try composer.run(using: stub)
        #expect(stub.calls[0].arguments.contains("release"))
        #expect(!stub.calls[0].arguments.contains("-g"))
    }
}

// MARK: - End-to-end (gated on WASM SDK presence)

@Suite("BuildCommand end-to-end (requires WASM SDK)")
struct BuildCommandIntegrationTests {

    static var wasmSDKAvailable: Bool {
        let runner = SystemProcessRunner()
        let result = try? runner.run(
            executable: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["swift", "sdk", "list"],
            workingDirectory: nil,
            environment: nil,
            captureOutput: true
        )
        guard let stdout = result?.standardOutput else { return false }
        return !WasmSDKProbe.parseSDKList(stdout).isEmpty
    }

    static var swiflowRepoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // SwiflowCLITests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
    }

    @Test(
        "swiflow init + swiflow build produces a PackageToJS output bundle",
        .enabled(if: wasmSDKAvailable)
    )
    func endToEnd() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiflow-e2e-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        // 1. Init into the temp dir, pointing at this checkout.
        try ProjectWriter.writeProject(
            name: "Demo",
            into: tmp,
            swiflowDep: .path(Self.swiflowRepoRoot.path),
            jsDriverSource: EmbeddedDriver.javascriptSource
        )

        // 2. Probe the SDK from the same shell-out path the production code uses.
        let runner = SystemProcessRunner()
        guard let swift = try SwiftExecutableLocator.locate(using: runner) else {
            Issue.record("swift not on PATH; cannot run end-to-end test.")
            return
        }
        let probe = WasmSDKProbe(runner: runner, swiftExecutable: swift)
        guard let sdk = try probe.list().first else {
            Issue.record("WasmSDKProbe returned empty even though .enabled gated true; flaky CI?")
            return
        }
        let toolchainBundleID = MacToolchainProbe.swiftLatestBundleIdentifier()

        // 3. Build.
        let invocation = BuildInvocation(
            swiftExecutable: swift,
            projectPath: tmp.appendingPathComponent("Demo"),
            swiftSDK: sdk,
            toolchainBundleID: toolchainBundleID
        )
        let result = try invocation.run(using: runner)
        #expect(result.exitCode == 0)

        // 4. Assert the PackageToJS output exists.
        let outputDir = tmp.appendingPathComponent("Demo/.build/plugins/PackageToJS/outputs/Package")
        let indexJS = outputDir.appendingPathComponent("index.js")
        let appWASM = outputDir.appendingPathComponent("App.wasm")
        #expect(FileManager.default.fileExists(atPath: indexJS.path), "missing \(indexJS.path)")
        #expect(FileManager.default.fileExists(atPath: appWASM.path), "missing \(appWASM.path)")
    }
}
