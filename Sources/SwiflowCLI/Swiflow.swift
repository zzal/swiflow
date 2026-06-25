// Sources/SwiflowCLI/Swiflow.swift
//
// Entry point for the `swiflow` CLI binary. The `Swiflow` async root
// command holds the subcommand table; each subcommand lives in its own
// file under Commands/.
//
// This file is named `Swiflow.swift` (not `main.swift`) because Swift 6
// treats files named `main.swift` as script-style top-level code, which
// conflicts with the `@main` attribute that an `AsyncParsableCommand`
// root needs to be dispatched on its async `run()` overload. Renaming
// the file lets `@main` work correctly and prevents the runtime error
// "Asynchronous root command needs availability annotation".

import ArgumentParser

@main
public struct Swiflow: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "swiflow",
        abstract: "Swift-WASM developer ecosystem — scaffold and build Swiflow projects.",
        version: SwiflowVersion.current,
        subcommands: [InitCommand.self, BuildCommand.self, DevCommand.self, DoctorCommand.self, ThemeCommand.self],
        defaultSubcommand: nil
    )

    public init() {}
}
