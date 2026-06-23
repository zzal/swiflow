// Sources/SwiflowCLI/DriverInstaller.swift
//
// Writes the embedded JS runtime into a project directory, selecting the
// readable (dev) or esbuild-minified (build) variant via `minified:`.
//
// `swiflow init` scaffolds `swiflow-driver.js` / `swiflow-service-worker.js` once (via
// ProjectWriter), but a project that wasn't `init`-ed — e.g. an example
// scaffolded by copying another, or a checkout whose gitignored driver never
// got committed — would have no driver for `index.html` to load, so the page
// boots blank (404 on swiflow-driver.js). `swiflow dev` and `swiflow build`
// call this so the driver is always present.
//
// Re-emitting (rather than write-if-missing) is deliberate: the driver is a
// GENERATED artifact whose source of truth is `js-driver/` → `EmbeddedDriver`
// (kept byte-identical by the embed freshness test). Overwriting keeps the
// served/served-from-disk driver in lockstep with the running CLI version, the
// same way `swiflow build` always rewrites `swiflow-manifest.json`.
//
// The region pair (`swiflow-regions.js` + `swiflow-region-guest.js`) is written
// only when the project's `index.html` references `swiflow-regions.js`
// (detected via `RuntimeFiles.usesRegions`).

import Foundation

enum DriverInstaller {
    /// Writes the runtime JS into `projectDir`, overwriting existing copies.
    /// `swiflow-driver.js` + `swiflow-service-worker.js` are always written.
    /// The region pair (`swiflow-regions.js` + `swiflow-region-guest.js`) is
    /// written only when the project's `index.html` references the regions
    /// script (see `RuntimeFiles.usesRegions`). `minified` selects the
    /// readable (dev) or esbuild-minified (build) variant.
    static func install(into projectDir: URL, minified: Bool) throws {
        let driver = minified ? EmbeddedDriver.javascriptSourceMinified : EmbeddedDriver.javascriptSource
        let sw = minified ? EmbeddedDriver.serviceWorkerSourceMinified : EmbeddedDriver.serviceWorkerSource
        try driver.write(to: projectDir.appendingPathComponent("swiflow-driver.js"), atomically: true, encoding: .utf8)
        try sw.write(to: projectDir.appendingPathComponent("swiflow-service-worker.js"), atomically: true, encoding: .utf8)

        guard projectUsesRegions(projectDir) else { return }
        let regions = minified ? EmbeddedDriver.regionsSourceMinified : EmbeddedDriver.regionsSource
        let guest = minified ? EmbeddedDriver.guestSdkSourceMinified : EmbeddedDriver.guestSdkSource
        try regions.write(to: projectDir.appendingPathComponent("swiflow-regions.js"), atomically: true, encoding: .utf8)
        try guest.write(to: projectDir.appendingPathComponent("swiflow-region-guest.js"), atomically: true, encoding: .utf8)
    }

    /// Re-emits `swiflow-service-worker.js` with the build tag stamped in. Called by
    /// `swiflow build` AFTER the manifest is written, so the tag reflects the
    /// artifacts actually being served. A changed tag changes the SW file's
    /// bytes, which is what makes the browser's update check re-fire
    /// `install` and precache the new manifest — without this, returning
    /// visitors stay pinned to the first-ever-cached bundle.
    /// `minified` must match the variant written by `install` for this build
    /// so the served SW stays consistent.
    static func stampServiceWorker(into projectDir: URL, buildTag: String, minified: Bool) throws {
        let base = minified ? EmbeddedDriver.serviceWorkerSourceMinified : EmbeddedDriver.serviceWorkerSource
        let stamped = base.replacingOccurrences(of: "__SWIFLOW_BUILD_TAG__", with: buildTag)
        try stamped.write(
            to: projectDir.appendingPathComponent("swiflow-service-worker.js"),
            atomically: true,
            encoding: .utf8
        )
    }

    private static func projectUsesRegions(_ projectDir: URL) -> Bool {
        let indexURL = projectDir.appendingPathComponent("index.html")
        guard let html = try? String(contentsOf: indexURL, encoding: .utf8) else { return false }
        return RuntimeFiles.usesRegions(indexHTML: html)
    }
}
