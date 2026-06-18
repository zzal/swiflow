#!/usr/bin/env swift
// scripts/embed-templates.swift
//
// One-shot codegen script. Run from the repo root:
//
//     swift scripts/embed-templates.swift
//
// Walks examples/*/, normalizes per-example tokens, and writes
// Sources/SwiflowCLI/EmbeddedTemplates.swift.
//
// The logic is duplicated from Sources/SwiflowCLI/TemplateEmbedder.swift
// because the script runs standalone (no SPM context, can't import
// SwiflowCLI). The TemplateEmbedderTests freshness test catches drift
// between this script and TemplateEmbedder.swiftSource.

import Foundation

let fm = FileManager.default
let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
let examplesRoot = cwd.appendingPathComponent("examples")
let outPath = cwd.appendingPathComponent("Sources/SwiflowCLI/EmbeddedTemplates.swift")

guard fm.fileExists(atPath: examplesRoot.path) else {
    FileHandle.standardError.write(Data("error: \(examplesRoot.path) not found. Run from repo root.\n".utf8))
    exit(1)
}

// `RegionDemo` is a repo feature-demo (its wasm guest builds from source via
// js-driver's asc), not a `swiflow init` starter — and it carries a binary
// `universe.wasm` that can't round-trip this UTF-8 codegen. Excluded whole.
let blacklist: Set<String> = [
    ".build", ".swiftpm", ".DS_Store", "Package.resolved",
    "swiflow-driver.js", "swiflow-sw.js", "swiflow-manifest.json",
    "RegionDemo",
]

func normalize(_ raw: String, exampleName: String, relativePath: String) -> String {
    var out = raw.replacingOccurrences(of: exampleName, with: "{{NAME}}")
    if relativePath == "Package.swift" {
        out = out.replacingOccurrences(
            of: #".package(path: "../..")"#,
            with: "{{SWIFLOW_DEP}}"
        )
    }
    return out
}

func relativePath(from base: URL, to file: URL) -> String {
    let basePath = base.path.hasSuffix("/") ? base.path : base.path + "/"
    return String(file.path.dropFirst(basePath.count))
}

func collectFiles(in dir: URL, exampleName: String) throws -> [(String, String)] {
    guard let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: [.isDirectoryKey]) else {
        return []
    }
    var results: [(String, String)] = []
    for case let url as URL in enumerator {
        let name = url.lastPathComponent
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        if blacklist.contains(name) {
            if isDir { enumerator.skipDescendants() }
            continue
        }
        if isDir { continue }
        let rel = relativePath(from: dir, to: url)
        let raw = try String(contentsOf: url, encoding: .utf8)
        guard raw.hasSuffix("\n") else {
            FileHandle.standardError.write(Data(
                "error: \(url.path) does not end with a newline. Add a trailing \\n so the codegen round-trip stays exact.\n".utf8
            ))
            exit(1)
        }
        results.append((rel, normalize(raw, exampleName: exampleName, relativePath: rel)))
    }
    return results.sorted { $0.0 < $1.0 }
}

do {
    let entries = try fm.contentsOfDirectory(
        at: examplesRoot,
        includingPropertiesForKeys: [.isDirectoryKey]
    )
    let templateDirs = entries
        .filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                && !blacklist.contains(url.lastPathComponent)
        }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

    var out = """
    // GENERATED FILE \u{2014} do not edit.
    //
    // Regenerate by running, from the repo root:
    //     swift scripts/embed-templates.swift
    //
    // Source: examples/*/

    enum EmbeddedTemplates {
        struct Template {
            let name: String
            let files: [String: String]
        }

        static let all: [Template] = [

    """

    for dir in templateDirs {
        let name = dir.lastPathComponent
        let files = try collectFiles(in: dir, exampleName: name)
        out += "        Template(\n"
        out += "            name: \"\(name)\",\n"
        out += "            files: [\n"
        for (path, contents) in files {
            out += "                \"\(path)\": ##\"\"\"\n\(contents)\n\"\"\"##,\n"
        }
        out += "            ]\n"
        out += "        ),\n"
    }

    out += """
        ]

        static func lookup(_ name: String) -> Template? {
            return all.first(where: { $0.name == name })
        }

        static var availableNames: [String] {
            return all.map(\\.name)
        }
    }

    """

    try out.write(to: outPath, atomically: true, encoding: .utf8)
    print("wrote \(outPath.path) (\(out.utf8.count) bytes)")
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
