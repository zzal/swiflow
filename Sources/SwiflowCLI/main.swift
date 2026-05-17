// Sources/SwiflowCLI/main.swift
//
// Entry point for the `swiflow` CLI binary. The `Swiflow` async root
// command holds the subcommand table; each subcommand lives in its own
// file under Commands/.
//
// Note: this file is literally named `main.swift`, which SwiftPM treats
// as script-style top-level code. That precludes using the `@main`
// attribute on the struct (the two entry-point mechanisms conflict
// under Swift 6.x). The canonical pattern in that case is the explicit
// `await Swiflow.main()` call at the bottom of this file.

import ArgumentParser

public struct Swiflow: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "swiflow",
        abstract: "Swift-WASM developer ecosystem — scaffold and build Swiflow projects.",
        version: "0.1.0",
        subcommands: [InitCommand.self, BuildCommand.self],
        defaultSubcommand: nil
    )

    public init() {}
}

await Swiflow.main()
