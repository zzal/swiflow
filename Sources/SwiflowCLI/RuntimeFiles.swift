// Sources/SwiflowCLI/RuntimeFiles.swift
//
// Shared rules about which runtime JS files a project needs. Pure and
// side-effect-free so the predicate is unit-tested without touching disk.

import Foundation

enum RuntimeFiles {
    /// A project uses the region runtime iff its `index.html` references the
    /// regions entrypoint script. Region templates carry
    /// `<script type="module" src="swiflow-regions.js">`; plain templates do
    /// not — so this substring is the single source of truth for "is this a
    /// region project", driving whether `swiflow-regions.js` /
    /// `swiflow-region-guest.js` get emitted.
    static func usesRegions(indexHTML: String) -> Bool {
        indexHTML.contains("swiflow-regions.js")
    }
}
