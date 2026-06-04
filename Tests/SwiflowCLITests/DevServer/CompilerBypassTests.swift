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
        try "import SwiflowWeb\nlet x = 1\n".write(to: f, atomically: true, encoding: .utf8)
        let k1 = key(src, root)
        try "import SwiflowWeb\nlet x = 2 // changed body\n".write(to: f, atomically: true, encoding: .utf8)
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
        try "import SwiflowWeb\nlet x = 1\n".write(to: f, atomically: true, encoding: .utf8)
        let k1 = key(src, root)
        try "import SwiflowWeb\nimport SwiflowQuery\nlet x = 1\n".write(to: f, atomically: true, encoding: .utf8)
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
        try "import SwiflowWeb\nlet x = 1\n".write(to: f, atomically: true, encoding: .utf8)
        let k1 = key(src, root)
        // Adding a @preconcurrency import must flip the key (it imports a new module).
        try "import SwiflowWeb\n@preconcurrency import Dispatch\nlet x = 1\n".write(to: f, atomically: true, encoding: .utf8)
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
        try "import SwiflowWeb\nlet x = 1\n".write(to: f, atomically: true, encoding: .utf8)
        let k1 = key(src, root)
        // A comment mentioning import and an identifier named `importer` must NOT flip the key.
        try "import SwiflowWeb\n// import Foundation\nlet importer = 1\nlet x = 1\n".write(to: f, atomically: true, encoding: .utf8)
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
