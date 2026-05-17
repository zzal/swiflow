// Sources/SwiflowCLI/Commands/BuildCommand.swift
//
// `swiflow build` — compiles a Swiflow project to a browser-loadable
// PackageToJS bundle. The action body lives in T9; this task only locks
// the argument shape.

import ArgumentParser
import Foundation

struct BuildCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "build",
        abstract: "Build a Swiflow project to a browser-loadable WASM bundle."
    )

    @Option(
        name: .customLong("path"),
        help: "Path to the Swiflow project directory. Defaults to the current working directory."
    )
    var path: String = "."

    @Option(
        name: .customLong("swift-sdk"),
        help: ArgumentHelp(
            "Override the Swift WASM SDK identifier.",
            discussion: """
                When unset, swiflow runs `swift sdk list` and picks the first installed \
                WASM SDK. Use this flag to pin to a specific SDK across machines.
                """
        )
    )
    var swiftSDK: String?

    func run() async throws {
        // Filled in by T9.
        throw ValidationError("BuildCommand.run() not yet implemented (T9).")
    }
}
