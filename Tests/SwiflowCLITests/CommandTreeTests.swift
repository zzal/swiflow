// Tests/SwiflowCLITests/CommandTreeTests.swift
import ArgumentParser
import Testing
@testable import SwiflowCLI

extension ParsableCommand {
    static var _commandName: String { configuration.commandName ?? "\(self)" }
}

@Suite("Command tree")
struct CommandTreeTests {
    @Test("Swiflow root command exposes init and build subcommands")
    func subcommandsRegistered() {
        let names = Swiflow.configuration.subcommands.map { $0._commandName }
        #expect(names.contains("init"))
        #expect(names.contains("build"))
    }

    @Test("InitCommand parses a name argument")
    func initParses() throws {
        let cmd = try InitCommand.parse(["my-app"])
        #expect(cmd.name == "my-app")
    }

    @Test("InitCommand parses --swiflow-source")
    func initParsesSwiflowSource() throws {
        let cmd = try InitCommand.parse(["demo", "--swiflow-source", "/tmp/swiflow"])
        #expect(cmd.swiflowSource == "/tmp/swiflow")
    }

    @Test("BuildCommand parses --path and --swift-sdk")
    func buildParses() throws {
        let cmd = try BuildCommand.parse(["--path", "./demo", "--swift-sdk", "swift-6.3-RELEASE_wasm"])
        #expect(cmd.path == "./demo")
        #expect(cmd.swiftSDK == "swift-6.3-RELEASE_wasm")
    }
}
