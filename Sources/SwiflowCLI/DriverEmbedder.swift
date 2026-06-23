// Sources/SwiflowCLI/DriverEmbedder.swift
//
// Pure formatting function used by both the codegen script
// (scripts/embed-driver.swift) and the freshness test
// (Tests/SwiflowCLITests/DriverEmbedderTests.swift). Keeping it here means
// the codegen logic is itself under test.

import Foundation

enum DriverEmbedder {
    /// Produces the Swift source for `EmbeddedDriver.swift` that wraps both
    /// the JS driver source and the service-worker source as raw string literals.
    ///
    /// We use Swift's extended-delimiter raw string (`#"""..."""#`) so that
    /// any quotes, backslashes, or string-interpolation markers in the JS
    /// source pass through untouched. The JS driver currently contains
    /// neither `"""#` nor `#"""`, but defensively bumping to `##"""..."""##`
    /// would be wise if a future JS edit ever introduced one.
    static func swiftSource(driverJS: String, swJS: String, regionsJS: String, guestSdkJS: String) -> String {
        // Swift multi-line strings strip ONE newline immediately after the
        // opening delimiter and ONE immediately before the closing delimiter.
        // So to round-trip a JS source `V` (which itself ends in `\n`)
        // verbatim, the literal between `#"""` and `"""#` must be
        // `\n` + V + `\n`. We achieve that by interpolating `\(...)` on its
        // own line and putting `"""#` on the next line — the trailing `\n`
        // of the source lands inside the raw-string body, and the next `\n`
        // (the one that ends the interpolation line) is the one Swift strips.
        return """
        // GENERATED FILE — do not edit.
        //
        // Regenerate by running, from the repo root:
        //     swift scripts/embed-driver.swift
        //
        // Source: js-driver/swiflow-driver.js + js-driver/swiflow-service-worker.js + js-driver/swiflow-regions.js + js-driver/swiflow-region-guest.js

        enum EmbeddedDriver {
            static let javascriptSource: String = #\"\"\"
        \(driverJS)
        \"\"\"#

            static let serviceWorkerSource: String = #\"\"\"
        \(swJS)
        \"\"\"#

            static let regionsSource: String = #\"\"\"
        \(regionsJS)
        \"\"\"#

            static let guestSdkSource: String = #\"\"\"
        \(guestSdkJS)
        \"\"\"#
        }
        """ + "\n"
    }
}
