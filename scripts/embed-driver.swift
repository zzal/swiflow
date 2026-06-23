#!/usr/bin/env swift
// scripts/embed-driver.swift
//
// One-shot codegen script. Run from the repo root:
//
//     swift scripts/embed-driver.swift
//
// Reads js-driver/swiflow-driver.js and writes
// Sources/SwiflowCLI/EmbeddedDriver.swift using DriverEmbedder.swiftSource.
//
// Why a script and not a SwiftPM plugin: SwiftPM plugins can't write to
// arbitrary paths in the package source tree (they're sandboxed to a
// per-target build dir). For codegen that we want under git, a thin
// scripted approach is simpler.

import Foundation

let fm = FileManager.default
let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)

let jsPath      = cwd.appendingPathComponent("js-driver/swiflow-driver.js")
let swPath      = cwd.appendingPathComponent("js-driver/swiflow-service-worker.js")
let regionsPath  = cwd.appendingPathComponent("js-driver/swiflow-regions.js")
let guestSdkPath = cwd.appendingPathComponent("js-driver/swiflow-region-guest.js")
let outPath      = cwd.appendingPathComponent("Sources/SwiflowCLI/EmbeddedDriver.swift")

for path in [jsPath, swPath, regionsPath, guestSdkPath] {
    guard fm.fileExists(atPath: path.path) else {
        FileHandle.standardError.write(Data("error: \(path.path) not found. Run from repo root.\n".utf8))
        exit(1)
    }
}

let js: String
let sw: String
let regions: String
let guestSdk: String
do {
    js       = try String(contentsOf: jsPath, encoding: .utf8)
    sw       = try String(contentsOf: swPath, encoding: .utf8)
    regions  = try String(contentsOf: regionsPath, encoding: .utf8)
    guestSdk = try String(contentsOf: guestSdkPath, encoding: .utf8)
} catch {
    FileHandle.standardError.write(Data("error: failed to read source files: \(error)\n".utf8))
    exit(1)
}

// We re-implement DriverEmbedder.swiftSource inline because this script
// runs standalone (no SPM context, can't `import SwiflowCLI`). The format
// must stay in sync with DriverEmbedder; the freshness test will catch
// any drift between this script and DriverEmbedder.swiftSource.
// Swift multi-line raw strings strip one \n after the opening delimiter
// and one \n before the closing delimiter. Each JS file already ends in
// "\n", so to round-trip each file byte-for-byte we want the literal
// between #""" and """# to be \n + <contents> + \n. That's accomplished
// by putting \(...) on its own line and """# on the line below: the line
// break after the interpolation is the stripped trailing \n, and the JS's
// own final \n stays inside the string body.
let output = """
// GENERATED FILE — do not edit.
//
// Regenerate by running, from the repo root:
//     swift scripts/embed-driver.swift
//
// Source: js-driver/swiflow-driver.js + js-driver/swiflow-service-worker.js + js-driver/swiflow-regions.js + js-driver/swiflow-region-guest.js

enum EmbeddedDriver {
    static let javascriptSource: String = #\"\"\"
\(js)
\"\"\"#

    static let serviceWorkerSource: String = #\"\"\"
\(sw)
\"\"\"#

    static let regionsSource: String = #\"\"\"
\(regions)
\"\"\"#

    static let guestSdkSource: String = #\"\"\"
\(guestSdk)
\"\"\"#
}
""" + "\n"

do {
    try output.write(to: outPath, atomically: true, encoding: .utf8)
} catch {
    FileHandle.standardError.write(Data("error: failed to write \(outPath.path): \(error)\n".utf8))
    exit(1)
}

print("wrote \(outPath.path) (\(output.utf8.count) bytes)")
