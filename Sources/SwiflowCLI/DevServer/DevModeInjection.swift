// Sources/SwiflowCLI/DevServer/DevModeInjection.swift
//
// Pure string transform that puts a `<script>window.SWIFLOW_DEV=true;</script>`
// tag into served HTML so the embedded JS driver's reload-WS branch
// activates. Lives in its own file so route handlers stay thin and so
// the transform can be exercised without spinning up a Hummingbird app.
//
// The injected script MUST run before the driver IIFE, otherwise the
// driver evaluates `window.SWIFLOW_DEV` as undefined and the WS branch
// stays inert for the page lifetime.

import Foundation

enum DevModeInjection {
    /// Marker substring used both to inject and to detect idempotency.
    /// Phase 8 adds SWIFLOW_HMR alongside SWIFLOW_DEV — we re-target
    /// the marker on the HMR flag because that one is the newer
    /// addition; idempotency still works because we always inject both
    /// or neither.
    static let marker = "window.SWIFLOW_HMR=true"

    /// The literal tag inserted into the response body. Both globals
    /// must be set before the driver IIFE runs so its dev/HMR branches
    /// activate together.
    private static let snippet = "<script>window.SWIFLOW_DEV=true;window.SWIFLOW_HMR=true;</script>"

    /// Returns `html` with a dev-mode signal injected. If the input
    /// already contains the marker, returns it unchanged (idempotent so
    /// double-application is safe — e.g., when middleware order shifts).
    /// Looks for the first `<script src="swiflow-driver.js"` tag and
    /// inserts immediately before it; falls back to `</body>`; if
    /// neither is present, returns the input unmodified.
    static func injectDevSignal(into html: String) -> String {
        guard !html.contains(marker) else { return html }

        if let driverRange = html.range(of: "<script src=\"swiflow-driver.js") {
            return html.replacingCharacters(in: driverRange.lowerBound..<driverRange.lowerBound, with: snippet)
        }
        if let bodyCloseRange = html.range(of: "</body>") {
            return html.replacingCharacters(in: bodyCloseRange.lowerBound..<bodyCloseRange.lowerBound, with: snippet)
        }
        return html
    }
}
