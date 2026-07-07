// Tests/SwiflowCLITests/SwiftContextTests.swift
//
// Audit III Wave-2 #10: the invocation preamble has one owner. These pin
// the preamble itself; the per-shape argv policies stay pinned in
// BuildCommandTests / CompilerBypassTests / FastRebuildTests, which now
// exercise the same code path through their types.
import Foundation
import Testing
@testable import SwiflowCLI

@Suite("SwiftContext — the invocation preamble's one owner")
struct SwiftContextTests {

    private var context: SwiftContext {
        SwiftContext(
            swift: URL(fileURLWithPath: "/toolchains/bin/swift"),
            projectPath: URL(fileURLWithPath: "/tmp/demo"),
            sdk: "swift-6.3.2-RELEASE_wasm",
            toolchainBundleID: "org.swift.632"
        )
    }

    @Test("run() composes executable, project cwd, and TOOLCHAINS in one place")
    func preambleComposition() throws {
        let stub = StubProcessRunner(stubbedExitCode: 0)
        _ = try context.run(["build", "--anything"], using: stub, captureOutput: true)
        let call = try #require(stub.calls.first)
        #expect(call.executable.path == "/toolchains/bin/swift")
        #expect(call.workingDirectory?.path == "/tmp/demo")
        #expect(call.environment?["TOOLCHAINS"] == "org.swift.632")
        #expect(call.arguments == ["build", "--anything"])
    }

    @Test("a nil bundle ID means an inherited environment, not an empty override")
    func nilBundleInherits() throws {
        let stub = StubProcessRunner(stubbedExitCode: 0)
        let bare = SwiftContext(
            swift: URL(fileURLWithPath: "/usr/bin/swift"),
            projectPath: URL(fileURLWithPath: "/p"),
            sdk: "swift-6.3.2-RELEASE_wasm",
            toolchainBundleID: nil
        )
        _ = try bare.run(["--version"], using: stub, captureOutput: true)
        #expect(stub.calls[0].environment == nil)
    }

    @Test("construction from a ToolchainResolution carries every field")
    func resolutionConstruction() {
        let resolution = ToolchainResolution.Result(
            swift: URL(fileURLWithPath: "/t/swift"),
            sdk: "swift-6.3.2-RELEASE_wasm",
            toolchainBundleID: "org.swift.632"
        )
        let ctx = SwiftContext(resolution: resolution, projectPath: URL(fileURLWithPath: "/proj"))
        #expect(ctx.swift.path == "/t/swift")
        #expect(ctx.sdk == "swift-6.3.2-RELEASE_wasm")
        #expect(ctx.toolchainBundleID == "org.swift.632")
        #expect(ctx.projectPath.path == "/proj")
    }
}
