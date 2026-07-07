// Sources/SwiflowEmbedders/RuntimeCopySync.swift
//
// The generated runtime JS lives canonically in js-driver/ and as tracked
// per-example copies (7× swiflow-driver.js, 9× swiflow-service-worker.js,
// plus RegionDemo's regions pair). Those copies used to be refreshed by
// hand-`cp` after every js-driver edit — a step easy to forget and caught
// only by CI's embed-freshness diff. `swift run swiflow-codegen driver`
// now refreshes them by tool.
//
// Policy: REFRESH-EXISTING only. An example opts into a runtime file by
// having it (committed); the sync never seeds new copies, so adding an
// example doesn't silently grow the copy set.

import Foundation

package enum RuntimeCopySync {

    package struct Copy: Equatable {
        package let source: URL
        package let destination: URL
    }

    /// The canonical runtime files, relative to js-driver/.
    package static let runtimeFileNames = [
        "swiflow-driver.js",
        "swiflow-service-worker.js",
        "swiflow-regions.js",
        "swiflow-region-guest.js",
    ]

    /// Plans the refresh: for every `examples/<dir>/<runtime file>` that
    /// already exists, pair it with its js-driver/ source. Sorted for
    /// deterministic output/logging.
    package static func plan(jsDriverRoot: URL, examplesRoot: URL) throws -> [Copy] {
        let fm = FileManager.default
        let exampleDirs = try fm.contentsOfDirectory(
            at: examplesRoot,
            includingPropertiesForKeys: [.isDirectoryKey]
        )
        .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var copies: [Copy] = []
        for dir in exampleDirs {
            for name in runtimeFileNames {
                let dest = dir.appendingPathComponent(name)
                guard fm.fileExists(atPath: dest.path) else { continue }
                copies.append(Copy(
                    source: jsDriverRoot.appendingPathComponent(name),
                    destination: dest
                ))
            }
        }
        return copies
    }

    /// Executes a plan. Byte copies — the runtime files are served verbatim.
    package static func execute(_ copies: [Copy]) throws {
        for copy in copies {
            let bytes = try Data(contentsOf: copy.source)
            try bytes.write(to: copy.destination, options: .atomic)
        }
    }
}
