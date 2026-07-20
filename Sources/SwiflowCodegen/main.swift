// Sources/SwiflowCodegen/main.swift
//
// `swift run swiflow-codegen <driver|templates|all>` — the repo's codegen
// tool. Replaces the standalone scripts/*.swift
// codegen scripts, which each re-implemented the embedders' emit logic
// inline (they couldn't import SwiflowCLI); the byte-pin tests kept the
// copies honest, but two emit paths was one too many. This tool imports
// the REAL embedders, so the tests, the CI freshness gate, and the emit
// share a single implementation.
//
// Run from the repo root:
//   swift run swiflow-codegen driver     # EmbeddedDriver.swift + example runtime-JS copies
//   swift run swiflow-codegen templates  # EmbeddedTemplates.swift from examples/*/
//   swift run swiflow-codegen all        # both
//
// Deliberately NOT ArgumentParser: two verbs don't justify pulling the
// dependency into this target's build graph (CI builds this tool in the
// embed-freshness job, where a slim graph keeps the job fast).

import Foundation
import SwiflowEmbedders

let fm = FileManager.default
let repoRoot = URL(fileURLWithPath: fm.currentDirectoryPath)
let jsDriverRoot = repoRoot.appendingPathComponent("js-driver")
let examplesRoot = repoRoot.appendingPathComponent("examples")

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

@MainActor func requireRepoRoot() {
    guard fm.fileExists(atPath: jsDriverRoot.appendingPathComponent("swiflow-driver.js").path),
          fm.fileExists(atPath: examplesRoot.path) else {
        fail("run from the swiflow repo root (js-driver/ and examples/ not found under \(repoRoot.path))")
    }
}

// MARK: - esbuild

/// Minifies one runtime file via the PINNED esbuild (js-driver/node_modules —
/// `npm ci` in js-driver/ installs it). A floating esbuild would make the
/// minified constants unreproducible across machines and trip the CI
/// freshness diff. A trailing newline is appended when missing so the
/// raw-string wrapping stays uniform with the readable sources.
@MainActor func minify(_ path: URL, esm: Bool) -> String {
    let esbuild = jsDriverRoot.appendingPathComponent("node_modules/.bin/esbuild")
    guard fm.isExecutableFile(atPath: esbuild.path) else {
        fail("\(esbuild.path) not found — run `npm ci` in js-driver/")
    }
    let proc = Process()
    proc.executableURL = esbuild
    proc.arguments = [path.path, "--minify"] + (esm ? ["--format=esm"] : [])
    let out = Pipe(), err = Pipe()
    proc.standardOutput = out
    proc.standardError = err
    do { try proc.run() } catch {
        fail("failed to launch esbuild: \(error)")
    }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    proc.waitUntilExit()
    guard proc.terminationStatus == 0 else {
        let msg = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        fail("esbuild failed for \(path.lastPathComponent):\n\(msg)")
    }
    var s = String(decoding: data, as: UTF8.self)
    if !s.hasSuffix("\n") { s += "\n" }
    return s
}

// MARK: - Subcommands

@MainActor func runDriver() {
    let jsPath = jsDriverRoot.appendingPathComponent("swiflow-driver.js")
    let swPath = jsDriverRoot.appendingPathComponent("swiflow-service-worker.js")
    let regionsPath = jsDriverRoot.appendingPathComponent("swiflow-regions.js")
    let guestSdkPath = jsDriverRoot.appendingPathComponent("swiflow-region-guest.js")
    let outPath = repoRoot.appendingPathComponent("Sources/SwiflowCLI/EmbeddedDriver.swift")

    do {
        let js = try String(contentsOf: jsPath, encoding: .utf8)
        let sw = try String(contentsOf: swPath, encoding: .utf8)
        let regions = try String(contentsOf: regionsPath, encoding: .utf8)
        let guestSdk = try String(contentsOf: guestSdkPath, encoding: .utf8)

        let output = DriverEmbedder.swiftSource(
            driverJS: js, driverJSMinified: minify(jsPath, esm: false),
            swJS: sw, swJSMinified: minify(swPath, esm: false),
            regionsJS: regions, regionsJSMinified: minify(regionsPath, esm: true),
            guestSdkJS: guestSdk, guestSdkJSMinified: minify(guestSdkPath, esm: true)
        )
        try output.write(to: outPath, atomically: true, encoding: .utf8)
        print("wrote \(outPath.path) (\(output.utf8.count) bytes)")

        // Refresh the tracked per-example runtime-JS copies (7× driver,
        // 9× service worker, RegionDemo's regions pair) — previously a
        // hand-`cp` step that was easy to forget.
        let copies = try RuntimeCopySync.plan(jsDriverRoot: jsDriverRoot, examplesRoot: examplesRoot)
        try RuntimeCopySync.execute(copies)
        print("refreshed \(copies.count) example runtime-JS copies")
    } catch {
        fail("\(error)")
    }
}

@MainActor func runTemplates() {
    let outPath = repoRoot.appendingPathComponent("Sources/SwiflowCLI/EmbeddedTemplates.swift")
    do {
        let output = try TemplateEmbedder.swiftSource(examplesRoot: examplesRoot)
        try output.write(to: outPath, atomically: true, encoding: .utf8)
        print("wrote \(outPath.path) (\(output.utf8.count) bytes)")
    } catch {
        fail("\(error)")
    }
}

// MARK: - Entry

requireRepoRoot()
switch CommandLine.arguments.dropFirst().first {
case "driver":
    runDriver()
case "templates":
    runTemplates()
case "all":
    runDriver()
    runTemplates()
default:
    print("""
    usage: swift run swiflow-codegen <driver|templates|all>

      driver     regenerate Sources/SwiflowCLI/EmbeddedDriver.swift from js-driver/
                 (pinned esbuild for the minified constants) and refresh the
                 tracked per-example runtime-JS copies
      templates  regenerate Sources/SwiflowCLI/EmbeddedTemplates.swift from examples/*/
      all        both
    """)
    exit(2)
}
