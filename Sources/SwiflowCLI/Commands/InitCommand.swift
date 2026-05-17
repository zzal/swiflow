// Sources/SwiflowCLI/Commands/InitCommand.swift
//
// `swiflow init <name>` — scaffolds a new Swiflow project from the embedded
// templates + driver. The action body lives in T5; this task only locks
// the argument shape.

import ArgumentParser
import Foundation

struct InitCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Scaffold a new Swiflow project."
    )

    @Argument(help: "The project name. A directory of this name will be created in the current working directory.")
    var name: String

    @Option(
        name: .customLong("swiflow-source"),
        help: ArgumentHelp(
            "Path or URL the generated project should use for its Swiflow dependency.",
            discussion: """
                Defaults to the relative path '../..', which lets generated projects \
                placed inside this repo's examples/ directory resolve their dependency \
                back to the parent checkout. After Phase 4 publishes Swiflow, this \
                default will flip to the official git URL.
                """
        )
    )
    var swiflowSource: String = "../.."

    func run() async throws {
        // Filled in by T5.
        throw ValidationError("InitCommand.run() not yet implemented (T5).")
    }
}
