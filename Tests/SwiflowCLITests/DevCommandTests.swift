// Tests/SwiflowCLITests/DevCommandTests.swift
import ArgumentParser
import Testing
@testable import SwiflowCLI

@Suite("DevCommand")
struct DevCommandTests {

    @Test("Defaults: --path is ., --port is 3000")
    func defaults() throws {
        let parsed = try DevCommand.parse([])
        #expect(parsed.path == ".")
        #expect(parsed.port == 3000)
        #expect(parsed.swiftSDK == nil)
    }

    @Test("Flags parse: --path, --port, --swift-sdk")
    func flags() throws {
        let parsed = try DevCommand.parse([
            "--path", "/tmp/demo",
            "--port", "4000",
            "--swift-sdk", "swift-6.3-RELEASE_wasm",
        ])
        #expect(parsed.path == "/tmp/demo")
        #expect(parsed.port == 4000)
        #expect(parsed.swiftSDK == "swift-6.3-RELEASE_wasm")
    }

    @Test("Appears in the root command's subcommand list")
    func registeredInRoot() {
        let names = Swiflow.configuration.subcommands.map { $0.configuration.commandName }
        #expect(names.contains("dev"))
    }
}
