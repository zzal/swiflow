// Sources/SwiflowCLI/main.swift
//
// Entry point for the `swiflow` CLI binary. The `Swiflow` async root
// command holds the subcommand table; each subcommand lives in its own
// file under Commands/.

import ArgumentParser

@main
public struct Swiflow: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "swiflow",
        abstract: "Swift-WASM developer ecosystem — scaffold and build Swiflow projects.",
        version: "0.1.0",
        subcommands: [],
        defaultSubcommand: nil
    )

    public init() {}
}
