// Sources/SwiflowCLI/DriverInstaller.swift
//
// Writes the embedded JS driver + service worker into a project directory.
//
// `swiflow init` scaffolds `swiflow-driver.js` / `swiflow-sw.js` once (via
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

import Foundation

enum DriverInstaller {
    /// Writes `swiflow-driver.js` and `swiflow-sw.js` from `EmbeddedDriver`
    /// into `projectDir`, overwriting any existing copies.
    static func install(into projectDir: URL) throws {
        try EmbeddedDriver.javascriptSource.write(
            to: projectDir.appendingPathComponent("swiflow-driver.js"),
            atomically: true,
            encoding: .utf8
        )
        try EmbeddedDriver.serviceWorkerSource.write(
            to: projectDir.appendingPathComponent("swiflow-sw.js"),
            atomically: true,
            encoding: .utf8
        )
    }

    /// Re-emits `swiflow-sw.js` with the build tag stamped in. Called by
    /// `swiflow build` AFTER the manifest is written, so the tag reflects the
    /// artifacts actually being served. A changed tag changes the SW file's
    /// bytes, which is what makes the browser's update check re-fire
    /// `install` and precache the new manifest — without this, returning
    /// visitors stay pinned to the first-ever-cached bundle.
    static func stampServiceWorker(into projectDir: URL, buildTag: String) throws {
        let stamped = EmbeddedDriver.serviceWorkerSource.replacingOccurrences(
            of: "__SWIFLOW_BUILD_TAG__",
            with: buildTag
        )
        try stamped.write(
            to: projectDir.appendingPathComponent("swiflow-sw.js"),
            atomically: true,
            encoding: .utf8
        )
    }
}
