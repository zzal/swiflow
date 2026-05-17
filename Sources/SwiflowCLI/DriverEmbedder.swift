// Sources/SwiflowCLI/DriverEmbedder.swift
//
// Pure formatting function used by both the codegen script
// (scripts/embed-driver.swift) and the freshness test
// (Tests/SwiflowCLITests/DriverEmbedderTests.swift). Keeping it here means
// the codegen logic is itself under test.

import Foundation

public enum DriverEmbedder {
    /// Produces the Swift source for `EmbeddedDriver.swift` that wraps the
    /// given JS driver source as a raw string literal.
    ///
    /// We use Swift's extended-delimiter raw string (`#"""..."""#`) so that
    /// any quotes, backslashes, or string-interpolation markers in the JS
    /// source pass through untouched. The JS driver currently contains
    /// neither `"""#` nor `#"""`, but defensively bumping to `##"""..."""##`
    /// would be wise if a future JS edit ever introduced one.
    public static func swiftSource(forJSSource js: String) -> String {
        // Swift multi-line strings strip ONE newline immediately after the
        // opening delimiter and ONE immediately before the closing delimiter.
        // So to round-trip a JS source `V` (which itself ends in `\n`)
        // verbatim, the literal between `#"""` and `"""#` must be
        // `\n` + V + `\n`. We achieve that by interpolating `\(js)` on its
        // own line and putting `"""#` on the next line — the trailing `\n`
        // of `js` lands inside the raw-string body, and the next `\n`
        // (the one that ends the `\(js)` line) is the one Swift strips.
        return """
        // GENERATED FILE — do not edit.
        //
        // Regenerate by running, from the repo root:
        //     swift scripts/embed-driver.swift
        //
        // Source: js-driver/swiflow-driver.js

        enum EmbeddedDriver {
            static let javascriptSource: String = #\"\"\"
        \(js)
        \"\"\"#
        }
        """ + "\n"
    }
}
