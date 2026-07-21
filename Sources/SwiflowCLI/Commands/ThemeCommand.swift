// Sources/SwiflowCLI/Commands/ThemeCommand.swift
//
// `swiflow theme --primary "oklch(0.62 0.17 255)"` — derive a contrast-validated
// --sw-accent override from a brand color and emit it (stdout, or --out file).
// Colors are OKLCH-primary: `oklch(L C H)` or hex (#rgb/#rrggbb). The whole accent
// family (hover/active/text/strong) derives from --sw-accent in SwiflowUI's base
// stylesheet, so the override re-points one token.

import ArgumentParser
import Foundation
import SwiflowColor

struct ThemeCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "theme",
        abstract: "Generate a contrast-validated --sw-accent override from a brand color."
    )

    @Option(name: .customLong("primary"),
            help: "Brand color (light-mode accent), as oklch(L C H) or hex (#rgb/#rrggbb).")
    var primary: String

    @Option(name: .customLong("out"),
            help: "Write the CSS to this file. Defaults to stdout.")
    var out: String?

    @Flag(name: .customLong("neutrals"),
          help: "Also derive the neutral ramp (surfaces/text/border), tinted to the accent.")
    var neutrals = false

    @Option(name: .customLong("danger"),
            help: "Brand danger/error color (light-mode), as oklch(L C H) or hex (#rgb/#rrggbb).")
    var danger: String?

    @Option(name: .customLong("success"),
            help: "Brand success color (light-mode), as oklch(L C H) or hex (#rgb/#rrggbb).")
    var success: String?

    @Option(name: .customLong("warning"),
            help: "Brand warning color (light-mode), as oklch(L C H) or hex (#rgb/#rrggbb).")
    var warning: String?

    @Option(name: .customLong("info"),
            help: "Brand info color (light-mode), as oklch(L C H) or hex; defaults to the accent if unset.")
    var info: String?

    func run() throws {
        let result = try ThemeGenerator.generate(.init(primary: primary,
                                                        danger: danger,
                                                        success: success,
                                                        warning: warning,
                                                        info: info,
                                                        includeNeutrals: neutrals))
        guard result.isValid else { throw ContrastFailuresError(failures: result.failures) }
        if let out {
            try result.css.write(toFile: out, atomically: true, encoding: .utf8)
        } else {
            print(result.css)
        }
    }
}

/// Reproduces the pre-public-API `PaletteError.contrastFailures` message so `swiflow theme`
/// output on a failing seed is byte-identical to before.
private struct ContrastFailuresError: Error, CustomStringConvertible {
    let failures: [PaletteFailure]
    var description: String {
        "brand color fails WCAG for the derived accent family:\n  "
            + failures.map(\.description).joined(separator: "\n  ")
    }
}
