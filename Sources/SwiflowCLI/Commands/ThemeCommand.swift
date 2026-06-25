// Sources/SwiflowCLI/Commands/ThemeCommand.swift
//
// `swiflow theme --primary "#hex"` — derive a contrast-validated --sw-accent
// override from a brand color and emit it (stdout, or --out file). The whole
// accent family (hover/active/text/strong) derives from --sw-accent in
// SwiflowUI's base stylesheet, so the override re-points one token.

import ArgumentParser
import Foundation
import SwiflowColor

struct ThemeCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "theme",
        abstract: "Generate a contrast-validated --sw-accent override from a brand color."
    )

    @Option(name: .customLong("primary"),
            help: "Brand color (light-mode accent), as #rgb or #rrggbb.")
    var primary: String

    @Option(name: .customLong("out"),
            help: "Write the CSS to this file. Defaults to stdout.")
    var out: String?

    func run() throws {
        let css = try Color.accentThemeCSS(primaryHex: primary)
        if let out {
            try css.write(toFile: out, atomically: true, encoding: .utf8)
        } else {
            print(css)
        }
    }
}
