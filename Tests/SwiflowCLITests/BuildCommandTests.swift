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
        // -Xswiftc flags are swift-package globals and must precede the `js`
        // plugin subcommand; -c release is a plugin flag and follows `js`.
        #expect(call.arguments == [
            "package",
            "--swift-sdk", "swift-6.3-RELEASE_wasm",
            "-Xswiftc", "-Osize",
            "-Xswiftc", "-gnone",
            "-Xswiftc", "-disable-reflection-metadata",
            "js",
            "--use-cdn",
            "--product", "App",
            "-c", "release",
        ])
        #expect(call.workingDirectory?.path == "/tmp/demo")
    }

    @Test("Release-mode invocation passes -Osize and -gnone via -Xswiftc")
    func releaseFlagsAreOsizeAndGnone() throws {
        let invocation = BuildInvocation(
            swiftExecutable: URL(fileURLWithPath: "/usr/bin/swift"),
            projectPath: URL(fileURLWithPath: "/tmp/demo"),
            swiftSDK: "swift-6.3-RELEASE_wasm",
            toolchainBundleID: nil,
            configuration: .release
        )
        let args = invocation.composeArguments()

        // -Osize and -gnone must each be passed via -Xswiftc (swift-package global flag)
        let xSwiftcIndices = args.indices.filter { args[$0] == "-Xswiftc" }
        let followers = xSwiftcIndices.compactMap { idx -> String? in
            let next = args.index(after: idx)
            return next < args.endIndex ? args[next] : nil
        }
        #expect(followers.contains("-Osize"))
        #expect(followers.contains("-gnone"))
    }

    @Test("Release-mode invocation passes -disable-reflection-metadata via -Xswiftc")
    func releaseDisablesReflectionMetadata() throws {
        let invocation = BuildInvocation(
            swiftExecutable: URL(fileURLWithPath: "/usr/bin/swift"),
            projectPath: URL(fileURLWithPath: "/tmp/demo"),
            swiftSDK: "swift-6.3-RELEASE_wasm",
            toolchainBundleID: nil,
            configuration: .release
        )
        let args = invocation.composeArguments()

        let xSwiftcIndices = args.indices.filter { args[$0] == "-Xswiftc" }
        let followers = xSwiftcIndices.map { args[args.index(after: $0)] }
        #expect(followers.contains("-disable-reflection-metadata"))
    }

    @Test("Dev-mode invocation does NOT pass -disable-reflection-metadata")
    func devKeepsReflectionMetadata() throws {
        let invocation = BuildInvocation(
            swiftExecutable: URL(fileURLWithPath: "/usr/bin/swift"),
            projectPath: URL(fileURLWithPath: "/tmp/demo"),
            swiftSDK: "swift-6.3-RELEASE_wasm",
            toolchainBundleID: nil,
            configuration: .dev
        )
        let args = invocation.composeArguments()
        #expect(!args.contains("-disable-reflection-metadata"))
    }

    @Test("Dev-mode invocation does NOT pass -Osize or -gnone")
    func devFlagsAreUnaffected() throws {
        let invocation = BuildInvocation(
            swiftExecutable: URL(fileURLWithPath: "/usr/bin/swift"),
            projectPath: URL(fileURLWithPath: "/tmp/demo"),
            swiftSDK: "swift-6.3-RELEASE_wasm",
            toolchainBundleID: nil,
            configuration: .dev
        )
        let args = invocation.composeArguments()
        #expect(!args.contains("-Osize"))
        #expect(!args.contains("-gnone"))
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
        // CI opt-out: these heavy real-build e2e tests crash the Swift 6.3.2
        // macro plugin repeatedly and eventually segfault the test process on
        // the Linux runner. CI sets SWIFLOW_SKIP_WASM_E2E to skip them; they
        // still run locally on any toolchain that has a WASM SDK. See ci.yml.
        // (DevCommandTests and InitCommandTests delegate to this gate.)
        if ProcessInfo.processInfo.environment["SWIFLOW_SKIP_WASM_E2E"] != nil { return false }
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
            template: EmbeddedTemplates.lookup("HelloWorld")!,
            into: tmp,
            swiflowDep: .path(Self.swiflowRepoRoot.path),
            jsDriverSource: EmbeddedDriver.javascriptSource,
            jsServiceWorkerSource: EmbeddedDriver.serviceWorkerSource
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

    @Test(
        "swiflow build writes swiflow-manifest.json with hashed artifacts",
        .enabled(if: wasmSDKAvailable)
    )
    func writesManifest() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiflow-manifest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        // 1. Scaffold a project pointing at this checkout.
        try ProjectWriter.writeProject(
            name: "Demo",
            template: EmbeddedTemplates.lookup("HelloWorld")!,
            into: tmp,
            swiflowDep: .path(Self.swiflowRepoRoot.path),
            jsDriverSource: EmbeddedDriver.javascriptSource,
            jsServiceWorkerSource: EmbeddedDriver.serviceWorkerSource
        )

        // 2. Probe swift + SDK (same path as production code).
        let runner = SystemProcessRunner()
        guard let swift = try SwiftExecutableLocator.locate(using: runner) else {
            Issue.record("swift not on PATH; cannot run manifest test.")
            return
        }
        let probe = WasmSDKProbe(runner: runner, swiftExecutable: swift)
        guard let sdk = try probe.list().first else {
            Issue.record("WasmSDKProbe returned empty even though .enabled gated true; flaky CI?")
            return
        }
        let toolchainBundleID = MacToolchainProbe.swiftLatestBundleIdentifier()

        // 3. Build via BuildInvocation (the same process-runner step production uses).
        let projectPath = tmp.appendingPathComponent("Demo")
        let invocation = BuildInvocation(
            swiftExecutable: swift,
            projectPath: projectPath,
            swiftSDK: sdk,
            toolchainBundleID: toolchainBundleID
        )
        let result = try invocation.run(using: runner)
        #expect(result.exitCode == 0)

        // 4. Write the manifest via the real production helper — not inline duplication.
        //    BuildCommand.writeManifest(projectDir:) is the exact code path that
        //    BuildCommand.run() calls in step 5; exercising it here gives the
        //    manifest-write block genuine test coverage.
        let manifestURL = projectPath.appendingPathComponent("swiflow-manifest.json")
        try BuildCommand.writeManifest(projectDir: projectPath)

        // 5. Verify the manifest on disk at the project root (where the SW
        //    expects it). URLs in the manifest must include the PackageToJS
        //    output-dir prefix so they resolve correctly against the SW's
        //    scope (the project root).
        #expect(FileManager.default.fileExists(atPath: manifestURL.path))
        let data = try Data(contentsOf: manifestURL)
        let decoded = try JSONDecoder().decode(BundleManifest.self, from: data)
        #expect(decoded.wasm.url.hasSuffix("App.wasm"))
        #expect(decoded.wasm.url.hasPrefix(".build/plugins/PackageToJS/outputs/Package/"))
        #expect(decoded.wasm.sha256.count == 64)
        #expect(decoded.runtime.count >= 4)
        for entry in decoded.runtime {
            #expect(entry.url.hasPrefix(".build/plugins/PackageToJS/outputs/Package/"),
                    "manifest runtime URL must carry the output-dir prefix; got '\(entry.url)'")
        }
    }
}
