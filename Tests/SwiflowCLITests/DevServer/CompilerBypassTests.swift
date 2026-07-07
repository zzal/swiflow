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

@Suite("BuildCommandParser")
struct BuildCommandParserTests {

    static var sample: String {
        get throws {
            let url = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()                   // DevServer
                .deletingLastPathComponent()                   // SwiflowCLITests
                .appendingPathComponent("Fixtures/swift-build-verbose-sample.txt")
            return try String(contentsOf: url, encoding: .utf8)
        }
    }

    @Test("Selects the -c App wasm compile job (not -emit-module, not the host line)")
    func picksCompileJob() throws {
        let parsed = try #require(BuildCommandParser.parse(verboseOutput: try Self.sample, appModule: "App"))
        #expect(parsed.compile.executable.path == "/tc/usr/bin/swiftc")
        #expect(parsed.compile.arguments.contains("-c"))
        #expect(parsed.compile.arguments.contains("-module-name"))
        #expect(parsed.compile.arguments.contains("App"))
        #expect(!parsed.compile.arguments.contains("-emit-module"))   // not the module-emit job
        // Quoted "-I" path survived tokenization as a single argument.
        #expect(parsed.compile.arguments.contains("/work/My Headers/inc"))
    }

    @Test("Selects the clang App.wasm link line (not the nested wasm-ld)")
    func picksLinkJob() throws {
        let parsed = try #require(BuildCommandParser.parse(verboseOutput: try Self.sample, appModule: "App"))
        #expect(parsed.link.executable.path == "/tc/usr/bin/clang")
        #expect(parsed.link.arguments.contains("-o"))
        #expect(parsed.link.arguments.contains { $0.hasSuffix("/App.wasm") })
    }

    @Test("Returns nil when the compile job is absent")
    func nilWhenNoCompile() {
        let noCompile = """
        /tc/usr/bin/clang -target wasm32-unknown-wasip1 -o /work/App.wasm @/work/list
        """
        #expect(BuildCommandParser.parse(verboseOutput: noCompile, appModule: "App") == nil)
    }

    @Test("Returns nil when two object-emitting App compile jobs are ambiguous")
    func nilWhenAmbiguous() throws {
        let dup = try Self.sample + "\n" +
            "/tc/usr/bin/swiftc -module-name App -target wasm32-unknown-wasip1 -c /work/Sources/App/Other.swift -o /work/.build/wasm32-unknown-wasip1/debug/App.build/Other.swift.o"
        #expect(BuildCommandParser.parse(verboseOutput: dup, appModule: "App") == nil)
    }

    @Test("shellSplit handles quoted segments and collapses whitespace")
    func tokenizer() {
        #expect(BuildCommandParser.shellSplit(#"a "b c" d"#) == ["a", "b c", "d"])
        #expect(BuildCommandParser.shellSplit("  x   y  ") == ["x", "y"])
        #expect(BuildCommandParser.shellSplit(#""/p/with space/x" -flag"#) == ["/p/with space/x", "-flag"])
    }

    @Test("Returns nil when no swiftc line matches the requested app module name")
    func nilWhenModuleNameMismatch() throws {
        #expect(BuildCommandParser.parse(verboseOutput: try Self.sample, appModule: "NotApp") == nil)
    }
}

@Suite("StalenessKey")
struct StalenessKeyTests {

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("stalekey-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func key(_ srcDir: URL, _ root: URL) -> StalenessKey {
        StalenessKey.compute(
            appSourcesDir: srcDir,
            manifestURL: root.appendingPathComponent("Package.swift"),
            resolvedURL: root.appendingPathComponent("Package.resolved")
        )
    }

    @Test("Stable across a file-body edit")
    func stableAcrossBodyEdit() throws {
        let root = try tempDir(); defer { try? FileManager.default.removeItem(at: root) }
        let src = root.appendingPathComponent("Sources/App")
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        let f = src.appendingPathComponent("App.swift")
        try "import SwiflowDOM\nlet x = 1\n".write(to: f, atomically: true, encoding: .utf8)
        let k1 = key(src, root)
        try "import SwiflowDOM\nlet x = 2 // changed body\n".write(to: f, atomically: true, encoding: .utf8)
        #expect(key(src, root) == k1)
    }

    @Test("sourceSet differs when a file is added")
    func differsOnAddedFile() throws {
        let root = try tempDir(); defer { try? FileManager.default.removeItem(at: root) }
        let src = root.appendingPathComponent("Sources/App")
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        try "let a = 1".write(to: src.appendingPathComponent("A.swift"), atomically: true, encoding: .utf8)
        let k1 = key(src, root)
        try "let b = 2".write(to: src.appendingPathComponent("B.swift"), atomically: true, encoding: .utf8)
        #expect(key(src, root) != k1)
        #expect(key(src, root).sourceSet.count == 2)
    }

    @Test("importHash differs when an import is added (file set unchanged)")
    func differsOnNewImport() throws {
        let root = try tempDir(); defer { try? FileManager.default.removeItem(at: root) }
        let src = root.appendingPathComponent("Sources/App")
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        let f = src.appendingPathComponent("App.swift")
        try "import SwiflowDOM\nlet x = 1\n".write(to: f, atomically: true, encoding: .utf8)
        let k1 = key(src, root)
        try "import SwiflowDOM\nimport SwiflowQuery\nlet x = 1\n".write(to: f, atomically: true, encoding: .utf8)
        let k2 = key(src, root)
        #expect(k2 != k1)
        #expect(k2.sourceSet == k1.sourceSet)   // same files, only imports changed
    }

    @Test("Recurses subdirectories; tolerates a missing Package.resolved")
    func recursesAndToleratesMissingResolved() throws {
        let root = try tempDir(); defer { try? FileManager.default.removeItem(at: root) }
        let src = root.appendingPathComponent("Sources/App")
        let sub = src.appendingPathComponent("Views")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try "let a = 1".write(to: src.appendingPathComponent("App.swift"), atomically: true, encoding: .utf8)
        try "let v = 1".write(to: sub.appendingPathComponent("View.swift"), atomically: true, encoding: .utf8)
        let k = key(src, root)               // no Package.swift / Package.resolved exist
        #expect(k.sourceSet.count == 2)      // recursed into Views/
        #expect(k.resolvedMTime == nil)
        #expect(k.manifestMTime == nil)
    }

    @Test("importHash differs when an attribute-prefixed import is added")
    func differsOnAttributePrefixedImport() throws {
        let root = try tempDir(); defer { try? FileManager.default.removeItem(at: root) }
        let src = root.appendingPathComponent("Sources/App")
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        let f = src.appendingPathComponent("App.swift")
        try "import SwiflowDOM\nlet x = 1\n".write(to: f, atomically: true, encoding: .utf8)
        let k1 = key(src, root)
        // Adding a @preconcurrency import must flip the key (it imports a new module).
        try "import SwiflowDOM\n@preconcurrency import Dispatch\nlet x = 1\n".write(to: f, atomically: true, encoding: .utf8)
        let k2 = key(src, root)
        #expect(k2 != k1)
        #expect(k2.sourceSet == k1.sourceSet)
    }

    @Test("A non-import line containing the word 'import' does NOT change the key")
    func ignoresImporterIdentifierAndComments() throws {
        let root = try tempDir(); defer { try? FileManager.default.removeItem(at: root) }
        let src = root.appendingPathComponent("Sources/App")
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        let f = src.appendingPathComponent("App.swift")
        try "import SwiflowDOM\nlet x = 1\n".write(to: f, atomically: true, encoding: .utf8)
        let k1 = key(src, root)
        // A comment mentioning import and an identifier named `importer` must NOT flip the key.
        try "import SwiflowDOM\n// import Foundation\nlet importer = 1\nlet x = 1\n".write(to: f, atomically: true, encoding: .utf8)
        let k2 = key(src, root)
        #expect(k2 == k1)
    }
}

@Suite("CommandReplayer")
struct CommandReplayerTests {

    private func sampleCommands() -> CapturedBuildCommands {
        CapturedBuildCommands(
            compile: ResolvedCommand(executable: URL(fileURLWithPath: "/tc/swiftc"), arguments: ["-c", "App.swift"]),
            link: ResolvedCommand(executable: URL(fileURLWithPath: "/tc/clang"), arguments: ["-o", "App.wasm"]),
            key: StalenessKey(sourceSet: [], importHash: 0, manifestMTime: nil, resolvedMTime: nil)
        )
    }

    @Test("Runs compile then link, in order, from the working directory")
    func runsBothInOrder() throws {
        let stub = StubProcessRunner(stubbedExitCode: 0)
        try CommandReplayer.replay(sampleCommands(), using: stub, workingDirectory: URL(fileURLWithPath: "/proj"))
        #expect(stub.calls.count == 2)
        #expect(stub.calls[0].executable.path == "/tc/swiftc")
        #expect(stub.calls[0].arguments == ["-c", "App.swift"])
        #expect(stub.calls[1].executable.path == "/tc/clang")
        #expect(stub.calls[1].arguments == ["-o", "App.wasm"])
        #expect(stub.calls[0].workingDirectory?.path == "/proj")
    }

    @Test("A non-zero compile exit throws and link does NOT run")
    func compileFailureStopsBeforeLink() {
        let stub = StubProcessRunner(stubbedExitCode: 4)   // first call (compile) fails
        #expect(throws: BuildCommandError.swiftBuildFailed(exitCode: 4)) {
            try CommandReplayer.replay(sampleCommands(), using: stub, workingDirectory: URL(fileURLWithPath: "/proj"))
        }
        #expect(stub.calls.count == 1)   // link never attempted
    }
}

@Suite("BypassRebuilder decision logic")
struct BypassRebuilderTests {

    // Builds a temp project (Sources/App + Package.swift), a fake raw-build
    // artifact, and a stale served wasm. Returns the rebuilder + temp root.
    private func fixture() throws -> (BypassRebuilder, URL, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("bypass-\(UUID().uuidString)")
        let src = root.appendingPathComponent("Sources/App")
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        try "import SwiflowDOM\nlet x = 1\n".write(to: src.appendingPathComponent("App.swift"), atomically: true, encoding: .utf8)
        try "// pkg".write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)

        let artifact = root.appendingPathComponent("App.wasm")           // "raw build output"
        try Data([0x00, 0x61, 0x73, 0x6D]).write(to: artifact)
        let served = root.appendingPathComponent("served.wasm")
        try Data([0xDE, 0xAD]).write(to: served)                         // stale

        let rebuilder = BypassRebuilder(
            capturingBuild: CapturingWasmBuildInvocation(
                swiftExecutable: URL(fileURLWithPath: "/usr/bin/swift"),
                projectPath: root, swiftSDK: "sdk", toolchainBundleID: nil
            ),
            fullBuild: BuildInvocation(
                swiftExecutable: URL(fileURLWithPath: "/usr/bin/swift"),
                projectPath: root, swiftSDK: "sdk", toolchainBundleID: nil, configuration: .dev
            ),
            appModule: "App",
            projectPath: root,
            appSourcesDir: src,
            manifestURL: root.appendingPathComponent("Package.swift"),
            resolvedURL: root.appendingPathComponent("Package.resolved"),
            artifactURL: artifact,
            outputWasmURL: served
        )
        return (rebuilder, root, served)
    }

    @Test("First save: capturing -v build, then a reactor re-link, then copies the wasm")
    func firstSaveCaptures() throws {
        let (rebuilder, root, served) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let stub = StubProcessRunner(stubbedExitCode: 0, stubbedStandardOutput: try BuildCommandParserTests.sample, stubbedStandardError: nil)
        var state = BypassState()

        try rebuilder.rebuild(using: stub, state: &state)

        // Capture (`swift build -v`) + a direct reactor re-link of the objects.
        #expect(stub.calls.count == 2)
        #expect(stub.calls[0].arguments.contains("-v"))          // the capturing build
        #expect(stub.calls[1].executable.path.hasSuffix("clang"))   // reactor re-link
        #expect(Array(stub.calls[1].arguments.suffix(3)) == BypassRebuilder.reactorLinkFlags)
        #expect(state.captured != nil)                          // commands captured
        #expect(state.bypassDisabled == false)
        // The stored link carries the reactor flags so every replay reproduces them.
        #expect(Array(state.captured?.link.arguments.suffix(3) ?? []) == BypassRebuilder.reactorLinkFlags)
        #expect(try Data(contentsOf: served) == Data([0x00, 0x61, 0x73, 0x6D]))  // copied
    }

    @Test("Second save, key unchanged: replays (compile + reactor link, no swift build)")
    func secondSaveReplays() throws {
        let (rebuilder, root, served) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let stub = StubProcessRunner(stubbedExitCode: 0, stubbedStandardOutput: try BuildCommandParserTests.sample, stubbedStandardError: nil)
        var state = BypassState()

        try rebuilder.rebuild(using: stub, state: &state)       // capture (2 calls: swift build -v, reactor re-link)
        try rebuilder.rebuild(using: stub, state: &state)       // replay (2 calls: swiftc, reactor clang)

        #expect(stub.calls.count == 4)
        #expect(stub.calls[2].executable.path.hasSuffix("swiftc"))
        #expect(stub.calls[3].executable.path.hasSuffix("clang"))
        // Neither replay call is a `swift build`.
        #expect(stub.calls[2].arguments.first != "build")
        #expect(stub.calls[3].arguments.first != "build")
        #expect(stub.calls[3].arguments.contains("-mexec-model=reactor"))   // replay uses the reactor link
        #expect(try Data(contentsOf: served) == Data([0x00, 0x61, 0x73, 0x6D]))  // replay still publishes the wasm
    }

    @Test("Source-set change re-captures (runs -v build again)")
    func fileSetChangeRecaptures() throws {
        let (rebuilder, root, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let stub = StubProcessRunner(stubbedExitCode: 0, stubbedStandardOutput: try BuildCommandParserTests.sample, stubbedStandardError: nil)
        var state = BypassState()

        try rebuilder.rebuild(using: stub, state: &state)       // capture: build -v + reactor re-link (2)
        // Add a file → sourceSet differs.
        try "let y = 2".write(to: root.appendingPathComponent("Sources/App/B.swift"), atomically: true, encoding: .utf8)
        try rebuilder.rebuild(using: stub, state: &state)       // must re-capture, not replay: build -v + re-link (2)

        #expect(stub.calls.count == 4)                          // 2 capturing builds (each + a re-link)
        #expect(stub.calls[0].arguments.contains("-v"))
        #expect(stub.calls[2].arguments.contains("-v"))         // the second capturing build
    }

    @Test("Parse failure latches bypassDisabled; capture and next save run the full plugin build")
    func parseFailureLatchesFallback() throws {
        let (rebuilder, root, served) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let stub = StubProcessRunner(stubbedExitCode: 0, stubbedStandardOutput: "garbage with no swiftc or clang lines", stubbedStandardError: nil)
        var state = BypassState()

        let fullBuildArgv = ["package", "--swift-sdk", "sdk", "js", "--use-cdn", "--product", "App", "--debug-info-format", "dwarf"]

        try rebuilder.rebuild(using: stub, state: &state)       // capture build runs, parse fails → full plugin build
        #expect(state.bypassDisabled == true)
        #expect(stub.calls.count == 2)
        #expect(stub.calls[0].arguments.contains("-v"))         // the capturing build
        #expect(stub.calls[1].arguments == fullBuildArgv)       // correctness fallback

        try rebuilder.rebuild(using: stub, state: &state)       // now latched: full plugin build only
        #expect(stub.calls.count == 3)
        #expect(stub.calls[2].arguments == fullBuildArgv)
        // The plugin writes the reactor wasm straight to the served path, so the
        // bypass does NOT copy — the stale fixture bytes are left untouched here.
        #expect(try Data(contentsOf: served) == Data([0xDE, 0xAD]))
    }
}

// MARK: - End-to-end (gated on WASM SDK presence)

/// Wraps a real runner, recording every call's argv while executing for real.
/// Lets the test assert which path (build vs replay) ran.
final class RecordingProcessRunner: ProcessRunner {
    let inner = SystemProcessRunner()
    private(set) var calls: [[String]] = []
    func run(executable: URL, arguments: [String], workingDirectory: URL?, environment: [String: String]?, captureOutput: Bool) throws -> ProcessResult {
        calls.append([executable.lastPathComponent] + arguments)
        return try inner.run(executable: executable, arguments: arguments, workingDirectory: workingDirectory, environment: environment, captureOutput: captureOutput)
    }
}

@Suite("BypassRebuilder end-to-end (requires WASM SDK)")
struct BypassRebuilderIntegrationTests {

    static var wasmSDKAvailable: Bool {
        // CI opt-out: skip this heavy real-build e2e under SWIFLOW_SKIP_WASM_E2E
        // (the Swift 6.3.2 macro plugin segfaults the test process on CI). Runs
        // locally on any toolchain with a WASM SDK. See ci.yml + BuildCommandIntegrationTests.
        if ProcessInfo.processInfo.environment["SWIFLOW_SKIP_WASM_E2E"] != nil { return false }
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

    @Test("capture → replay → recapture-on-new-file → replay; served wasm tracks each edit",
          .enabled(if: wasmSDKAvailable), .timeLimit(.minutes(15)))
    func realBypassLoop() async throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("swiflow-bypass-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        // 1. Scaffold HelloWorld pointing at this checkout.
        try ProjectWriter.writeProject(
            name: "Demo",
            template: EmbeddedTemplates.lookup("HelloWorld")!,
            into: tmp,
            swiflowDep: .path(Self.swiflowRepoRoot.path),
            jsDriverSource: EmbeddedDriver.javascriptSource,
            jsServiceWorkerSource: EmbeddedDriver.serviceWorkerSource,
            jsRegionsSource: EmbeddedDriver.regionsSource,
            jsGuestSdkSource: EmbeddedDriver.guestSdkSource
        )
        let projectPath = tmp.appendingPathComponent("Demo")
        let appSwift = projectPath.appendingPathComponent("Sources/App/App.swift")

        // 2. Probe swift + SDK + toolchain.
        let probeRunner = SystemProcessRunner()
        guard let swift = try SwiftExecutableLocator.locate(using: probeRunner) else { Issue.record("swift not on PATH"); return }
        guard let sdk = try WasmSDKProbe(runner: probeRunner, swiftExecutable: swift).list().first else { Issue.record("no SDK"); return }
        let toolchainBundleID = MacToolchainProbe.swiftLatestBundleIdentifier()

        // 3. Initial full build (produces the served glue + first wasm).
        let initial = BuildInvocation(swiftExecutable: swift, projectPath: projectPath, swiftSDK: sdk, toolchainBundleID: toolchainBundleID, configuration: .dev)
        #expect(try initial.run(using: probeRunner).exitCode == 0)

        let outputWasmURL = projectPath.appendingPathComponent(DevCommand.packageToJSOutputRelativePath).appendingPathComponent("App.wasm")
        let artifactURL = try #require(WasmArtifactLocator.resolve(context: SwiftContext(swift: swift, projectPath: projectPath, sdk: sdk, toolchainBundleID: toolchainBundleID), using: probeRunner))

        let rebuilder = BypassRebuilder(
            capturingBuild: CapturingWasmBuildInvocation(swiftExecutable: swift, projectPath: projectPath, swiftSDK: sdk, toolchainBundleID: toolchainBundleID),
            fullBuild: BuildInvocation(swiftExecutable: swift, projectPath: projectPath, swiftSDK: sdk, toolchainBundleID: toolchainBundleID, configuration: .dev),
            appModule: "App", projectPath: projectPath,
            appSourcesDir: projectPath.appendingPathComponent("Sources/App"),
            manifestURL: projectPath.appendingPathComponent("Package.swift"),
            resolvedURL: projectPath.appendingPathComponent("Package.resolved"),
            artifactURL: artifactURL, outputWasmURL: outputWasmURL
        )
        var state = BypassState()
        let runner = RecordingProcessRunner()

        func markerPresent(_ marker: String) throws -> Bool {
            let data = try Data(contentsOf: outputWasmURL)
            return data.range(of: Data(marker.utf8)) != nil
        }
        func injectExportedSymbol(_ name: String) throws {
            var src = try String(contentsOf: appSwift, encoding: .utf8)
            src += "\n@_cdecl(\"\(name)\") public func \(name)() -> Int32 { 0 }\n"
            try src.write(to: appSwift, atomically: true, encoding: .utf8)
        }

        // 4. First save (body edit) → capture. Served wasm gets marker M1.
        try injectExportedSymbol("bypass_marker_one")
        try rebuilder.rebuild(using: runner, state: &state)
        #expect(state.captured != nil)
        #expect(try markerPresent("bypass_marker_one"))
        // Regression guard for the command-vs-reactor ABI bug: the served wasm
        // must be a browser-loadable reactor. The reactor link exports
        // `__main_argc_argv` (what PackageToJS's glue calls as `swift.main()`);
        // a plain `swift build` command wasm has no such export. Byte-searching
        // the export name is a cheap proxy for "the reactor re-link ran".
        #expect(try markerPresent("__main_argc_argv"))
        let callsAfterCapture = runner.calls.count

        // 5. Second save (different body edit) → REPLAY (no swift build).
        try injectExportedSymbol("bypass_marker_two")
        try rebuilder.rebuild(using: runner, state: &state)
        #expect(try markerPresent("bypass_marker_two"))
        let replayCalls = runner.calls[callsAfterCapture...]
        #expect(!replayCalls.contains { $0.first == "swift" && $0.dropFirst().first == "build" })  // replayed, didn't build
        #expect(replayCalls.contains { $0.first?.hasSuffix("swiftc") == true })

        // 6. Add a NEW file with a function and REFERENCE it from App.swift via
        //    an exported symbol → sourceSet changes → re-capture must compile the
        //    new file, else the link fails on the undefined reference (a stronger
        //    check than relying on a dead-strippable unreferenced export).
        let newFile = projectPath.appendingPathComponent("Sources/App/Extra.swift")
        try "func extraValue() -> Int32 { 31337 }\n".write(to: newFile, atomically: true, encoding: .utf8)
        var withRef = try String(contentsOf: appSwift, encoding: .utf8)
        withRef += "\n@_cdecl(\"bypass_marker_three\") public func m3() -> Int32 { extraValue() }\n"
        try withRef.write(to: appSwift, atomically: true, encoding: .utf8)
        try rebuilder.rebuild(using: runner, state: &state)        // re-capture compiles Extra.swift
        #expect(try markerPresent("bypass_marker_three"))

        // 7. A further body edit after the re-capture must REPLAY correctly,
        //    proving the shared .build incremental state stays coherent across
        //    the replay → capture → replay alternation.
        try injectExportedSymbol("bypass_marker_four")
        try rebuilder.rebuild(using: runner, state: &state)        // replay after recapture
        #expect(try markerPresent("bypass_marker_four"))
        #expect(try markerPresent("bypass_marker_three"))          // earlier symbol still linked in
    }
}
