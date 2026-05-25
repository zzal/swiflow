// Tests/SwiflowCLITests/InitCommandTests.swift
import ArgumentParser
import Foundation
import Testing
@testable import SwiflowCLI

@Suite("InitCommand")
struct InitCommandTests {
    @Test("Init creates the expected file tree")
    func createsFileTree() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        try ProjectWriter.writeProject(
            name: "Demo",
            into: tmp,
            swiflowDep: .path("../.."),
            jsDriverSource: "// fake driver\n"
        )

        let project = tmp.appendingPathComponent("Demo")
        let fm = FileManager.default

        #expect(fm.fileExists(atPath: project.path))
        #expect(fm.fileExists(atPath: project.appendingPathComponent("Package.swift").path))
        #expect(fm.fileExists(atPath: project.appendingPathComponent("Sources/App/App.swift").path))
        #expect(fm.fileExists(atPath: project.appendingPathComponent("index.html").path))
        #expect(fm.fileExists(atPath: project.appendingPathComponent("swiflow-driver.js").path))
        #expect(fm.fileExists(atPath: project.appendingPathComponent(".gitignore").path))
        #expect(fm.fileExists(atPath: project.appendingPathComponent("README.md").path))
    }

    @Test("Init writes the embedded driver verbatim to swiflow-driver.js")
    func writesDriverVerbatim() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let driver = "// custom driver payload\nconsole.log('hi');\n"
        try ProjectWriter.writeProject(
            name: "Demo",
            into: tmp,
            swiflowDep: .path("../.."),
            jsDriverSource: driver
        )

        let url = tmp.appendingPathComponent("Demo/swiflow-driver.js")
        let onDisk = try String(contentsOf: url, encoding: .utf8)
        #expect(onDisk == driver)
    }

    @Test("Init refuses to overwrite an existing directory")
    func refusesOverwrite() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Pre-create the target so the writer collides.
        let collision = tmp.appendingPathComponent("Demo")
        try FileManager.default.createDirectory(at: collision, withIntermediateDirectories: true)

        #expect(throws: ProjectWriterError.targetExists(collision)) {
            try ProjectWriter.writeProject(
                name: "Demo",
                into: tmp,
                swiflowDep: .path("../.."),
                jsDriverSource: "// driver\n"
            )
        }
    }

    @Test("Init cleans up the target directory when a file write fails partway through")
    func cleansUpOnFailure() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Force a failure between createDirectory and the file writes.
        // ProjectWriter throws a CocoaError to simulate a real FileManager
        // write failure; targetExists (the precondition error) would be
        // semantically wrong here since the dir was just created by this call.
        var caught: Error?
        do {
            try ProjectWriter.writeProject(
                name: "Demo",
                into: tmp,
                swiflowDep: .path("/abs/path/to/swiflow"),
                jsDriverSource: "// driver\n",
                _testFailDuringWrites: true
            )
            Issue.record("expected writeProject to throw when _testFailDuringWrites is true")
        } catch {
            caught = error
        }
        #expect(caught != nil)

        // The target must not exist after the failure.
        let project = tmp.appendingPathComponent("Demo")
        #expect(!FileManager.default.fileExists(atPath: project.path),
                "ProjectWriter must remove the target directory when writes fail; found leftover at \(project.path)")
    }

    @Test("Init applies the swiflow-source argument to the generated Package.swift")
    func threadsSwiflowSource() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        try ProjectWriter.writeProject(
            name: "Demo",
            into: tmp,
            swiflowDep: .path("/abs/path/to/swiflow"),
            jsDriverSource: "// driver\n"
        )

        let pkg = try String(
            contentsOf: tmp.appendingPathComponent("Demo/Package.swift"),
            encoding: .utf8
        )
        #expect(pkg.contains(#".package(path: "/abs/path/to/swiflow")"#))
    }

    @Test("Generated App.swift uses @Component Counter with @State")
    func appSwiftIsCounterComponent() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        try ProjectWriter.writeProject(
            name: "Demo",
            into: tmp,
            swiflowDep: .path("../.."),
            jsDriverSource: "// driver\n"
        )

        let app = try String(
            contentsOf: tmp.appendingPathComponent("Demo/Sources/App/App.swift"),
            encoding: .utf8
        )
        // @Component macro replaces the explicit `: Component` conformance declaration.
        #expect(app.contains("@Component"))
        #expect(app.contains("final class Counter {"))
        #expect(app.contains("@State var count: Int = 0"))
        #expect(app.contains("Swiflow.render(into: \"#app\") { Counter() }"))
        let hasRerenderCall = app.contains("Swiflow.rerender()\n") || app.contains("            Swiflow.rerender()")
        #expect(!hasRerenderCall, "Counter shouldn't need explicit rerender — @State handles it")
    }

    // MARK: - Helpers

    fileprivate static func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiflow-init-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeTempDir() throws -> URL { try Self.makeTempDir() }
}

@Suite("InitCommand argv")
struct InitCommandArgvTests {

    @Test("Default: --path is .")
    func defaultPath() throws {
        let parsed = try InitCommand.parse(["demo", "--swiflow-source", "/some/path"])
        #expect(parsed.name == "demo")
        #expect(parsed.path == ".")
    }

    @Test("Missing --swiflow-source surfaces a ValidationError")
    func missingSwiflowSource() async throws {
        let cmd = try InitCommand.parse(["demo"])
        // run() checks swiflowSource before --path, so no valid dir needed
        await #expect(throws: ValidationError.self) {
            try await cmd.run()
        }
    }

    @Test("Flags parse: --path, --swiflow-source")
    func flags() throws {
        let parsed = try InitCommand.parse([
            "demo",
            "--path", "/tmp/parent",
            "--swiflow-source", "/abs/swiflow",
        ])
        #expect(parsed.name == "demo")
        #expect(parsed.path == "/tmp/parent")
        #expect(parsed.swiflowSource == "/abs/swiflow")
    }

    @Test("Appears in the root command's subcommand list")
    func registeredInRoot() {
        let names = Swiflow.configuration.subcommands.map { $0.configuration.commandName }
        #expect(names.contains("init"))
    }
}

@Suite("InitCommand run()")
struct InitCommandRunTests {

    @Test("--path routes the project to that directory")
    func respectsPath() async throws {
        let tmp = try InitCommandTests.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let cmd = try InitCommand.parse([
            "Demo",
            "--path", tmp.path,
            "--swiflow-source", "/abs/path/to/swiflow",
        ])
        try await cmd.run()

        let project = tmp.appendingPathComponent("Demo")
        let fm = FileManager.default
        #expect(fm.fileExists(atPath: project.appendingPathComponent("Package.swift").path))
        #expect(fm.fileExists(atPath: project.appendingPathComponent("Sources/App/App.swift").path))
        #expect(fm.fileExists(atPath: project.appendingPathComponent("swiflow-driver.js").path))
    }

    @Test("--path that doesn't exist surfaces a ValidationError")
    func refusesMissingPath() async throws {
        let cmd = try InitCommand.parse([
            "Demo",
            "--path", "/does/not/exist/swiflow-test-\(UUID().uuidString)",
            "--swiflow-source", "/abs/path/to/swiflow",
        ])
        await #expect(throws: ValidationError.self) {
            try await cmd.run()
        }
    }

    @Test("InitCommandError.parentPathNotFound has a useful description")
    func parentPathNotFoundDescription() {
        let url = URL(fileURLWithPath: "/does/not/exist")
        let error = InitCommandError.parentPathNotFound(url)
        let desc = String(describing: error)
        #expect(desc.contains("does not exist"))
        #expect(desc.contains("/does/not/exist"))
    }
}

// MARK: - End-to-end (gated on WASM SDK presence)

@Suite("InitCommand end-to-end integration (requires WASM SDK)")
struct InitCommandIntegrationTests {

    static var wasmSDKAvailable: Bool {
        BuildCommandIntegrationTests.wasmSDKAvailable
    }

    static var swiflowRepoRoot: URL {
        BuildCommandIntegrationTests.swiflowRepoRoot
    }

    @Test(
        "swiflow init end-to-end: InitCommand.run() produces a project that builds successfully",
        .enabled(if: wasmSDKAvailable)
    )
    func initCommandRunThenBuild() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiflow-init-e2e-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        // 1. Invoke the full InitCommand.run() — not just ProjectWriter directly.
        let cmd = try InitCommand.parse([
            "Demo",
            "--path", tmp.path,
            "--swiflow-source", Self.swiflowRepoRoot.path,
        ])
        try await cmd.run()

        // 2. Verify the project directory was created.
        let project = tmp.appendingPathComponent("Demo")
        let fm = FileManager.default
        #expect(fm.fileExists(atPath: project.appendingPathComponent("Package.swift").path))
        #expect(fm.fileExists(atPath: project.appendingPathComponent("Sources/App/App.swift").path))

        // 3. Build the scaffolded project.
        let runner = SystemProcessRunner()
        guard let swift = try SwiftExecutableLocator.locate(using: runner) else {
            Issue.record("swift not on PATH; cannot complete end-to-end test.")
            return
        }
        let probe = WasmSDKProbe(runner: runner, swiftExecutable: swift)
        guard let sdk = try probe.list().first else {
            Issue.record("WasmSDKProbe returned empty even though .enabled gated true; flaky CI?")
            return
        }
        let toolchainBundleID = MacToolchainProbe.swiftLatestBundleIdentifier()
        let invocation = BuildInvocation(
            swiftExecutable: swift,
            projectPath: project,
            swiftSDK: sdk,
            toolchainBundleID: toolchainBundleID
        )
        let result = try invocation.run(using: runner)
        #expect(result.exitCode == 0)

        // 4. Verify PackageToJS output exists.
        let outputDir = project.appendingPathComponent(".build/plugins/PackageToJS/outputs/Package")
        let indexJS = outputDir.appendingPathComponent("index.js")
        let appWASM = outputDir.appendingPathComponent("App.wasm")
        #expect(fm.fileExists(atPath: indexJS.path), "missing \(indexJS.path)")
        #expect(fm.fileExists(atPath: appWASM.path), "missing \(appWASM.path)")
    }
}
