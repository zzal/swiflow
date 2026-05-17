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

let jsPath = cwd.appendingPathComponent("js-driver/swiflow-driver.js")
let outPath = cwd.appendingPathComponent("Sources/SwiflowCLI/EmbeddedDriver.swift")

guard fm.fileExists(atPath: jsPath.path) else {
    FileHandle.standardError.write(Data("error: \(jsPath.path) not found. Run from repo root.\n".utf8))
    exit(1)
}

let js: String
do {
    js = try String(contentsOf: jsPath, encoding: .utf8)
} catch {
    FileHandle.standardError.write(Data("error: failed to read \(jsPath.path): \(error)\n".utf8))
    exit(1)
}

// We re-implement DriverEmbedder.swiftSource inline because this script
// runs standalone (no SPM context, can't `import SwiflowCLI`). The format
// must stay in sync with DriverEmbedder; the freshness test will catch
// any drift between this script and DriverEmbedder.swiftSource.
// Swift multi-line raw strings strip one \n after the opening delimiter
// and one \n before the closing delimiter. The JS file already ends in
// "\n", so to make EmbeddedDriver.javascriptSource round-trip the file
// byte-for-byte we want the literal between #""" and """# to be
// \n + <jsContents> + \n. That's accomplished by putting \(js) on its
// own line and """# on the line below: the line break after \(js) is
// the stripped trailing \n, and the JS's own final \n stays inside the
// string body.
let output = """
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

do {
    try output.write(to: outPath, atomically: true, encoding: .utf8)
} catch {
    FileHandle.standardError.write(Data("error: failed to write \(outPath.path): \(error)\n".utf8))
    exit(1)
}

print("wrote \(outPath.path) (\(output.utf8.count) bytes)")
