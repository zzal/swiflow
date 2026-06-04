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
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()                       // DevServer
            .deletingLastPathComponent()                       // SwiflowCLITests
            .appendingPathComponent("Fixtures/swift-build-verbose-sample.txt")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    @Test("Selects the -c App wasm compile job (not -emit-module, not the host line)")
    func picksCompileJob() throws {
        let parsed = try #require(BuildCommandParser.parse(verboseOutput: Self.sample, appModule: "App"))
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
        let parsed = try #require(BuildCommandParser.parse(verboseOutput: Self.sample, appModule: "App"))
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
    func nilWhenAmbiguous() {
        let dup = Self.sample + "\n" +
            "/tc/usr/bin/swiftc -module-name App -target wasm32-unknown-wasip1 -c /work/Sources/App/Other.swift -o /work/.build/wasm32-unknown-wasip1/debug/App.build/Other.swift.o"
        #expect(BuildCommandParser.parse(verboseOutput: dup, appModule: "App") == nil)
    }

    @Test("shellSplit handles quoted segments and collapses whitespace")
    func tokenizer() {
        #expect(BuildCommandParser.shellSplit(#"a "b c" d"#) == ["a", "b c", "d"])
        #expect(BuildCommandParser.shellSplit("  x   y  ") == ["x", "y"])
        #expect(BuildCommandParser.shellSplit(#""/p/with space/x" -flag"#) == ["/p/with space/x", "-flag"])
    }
}
