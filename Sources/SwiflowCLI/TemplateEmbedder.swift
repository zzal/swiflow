// Sources/SwiflowCLI/TemplateEmbedder.swift
//
// Pure codegen helper used by both the codegen script
// (scripts/embed-templates.swift) and the freshness test
// (Tests/SwiflowCLITests/TemplateEmbedderTests.swift). Same shape as
// DriverEmbedder.swift.
//
// Walks `examples/`, normalizes per-example tokens, and produces the
// Swift source for `EmbeddedTemplates.swift`. No file writes — the
// caller decides what to do with the returned string.

import Foundation

enum TemplateEmbedder {

    /// File / directory names excluded from every template.
    /// - `.build`, `Package.resolved`, `.DS_Store`: build artifacts and OS files.
    /// - `swiflow-driver.js`, `swiflow-sw.js`, `swiflow-manifest.json`:
    ///   the JS driver + service worker come from EmbeddedDriver (which is
    ///   itself codegen'd from js-driver/). Keeping them out of the template
    ///   avoids two paths for the same canonical bytes.
    static let blacklist: Set<String> = [
        ".build",
        ".DS_Store",
        "Package.resolved",
        "swiflow-driver.js",
        "swiflow-sw.js",
        "swiflow-manifest.json",
    ]

    struct TemplateData {
        let name: String
        /// Sorted by `relativePath` for deterministic codegen output.
        let files: [(relativePath: String, contents: String)]
    }

    // MARK: - Pure substitution (heavily tested)

    /// Applies the two codegen-time substitutions to a file's raw contents.
    ///
    /// - `{{NAME}}` ← every literal occurrence of `exampleName`.
    /// - `{{SWIFLOW_DEP}}` ← the literal line `.package(path: "../..")`, but
    ///   only in `Package.swift`. (We require all examples to use that exact
    ///   form so the substitution can stay a single dumb string replace.)
    static func normalize(_ raw: String, exampleName: String, relativePath: String) -> String {
        var out = raw.replacingOccurrences(of: exampleName, with: "{{NAME}}")
        if relativePath == "Package.swift" {
            out = out.replacingOccurrences(
                of: #".package(path: "../..")"#,
                with: "{{SWIFLOW_DEP}}"
            )
        }
        return out
    }

    // MARK: - Filesystem walk

    /// Walks `examplesRoot/*/`, collecting every template directory and its
    /// non-blacklisted files. Returns `TemplateData` sorted by name (so
    /// codegen output is deterministic regardless of directory enumeration order).
    static func collect(examplesRoot: URL) throws -> [TemplateData] {
        let fm = FileManager.default
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

        return try templateDirs.map { dir in
            let name = dir.lastPathComponent
            let files = try collectFiles(in: dir, exampleName: name)
            return TemplateData(name: name, files: files)
        }
    }

    /// Recursively collects non-blacklisted files. Returns relative paths
    /// (POSIX-style, slash-separated) sorted alphabetically for determinism.
    static func collectFiles(in dir: URL, exampleName: String) throws -> [(relativePath: String, contents: String)] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else {
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

            let rel = Self.relativePath(from: dir, to: url)
            let raw = try String(contentsOf: url, encoding: .utf8)
            let normalized = normalize(raw, exampleName: exampleName, relativePath: rel)
            results.append((rel, normalized))
        }
        return results.sorted { $0.0 < $1.0 }
    }

    private static func relativePath(from base: URL, to file: URL) -> String {
        let basePath = base.path.hasSuffix("/") ? base.path : base.path + "/"
        return String(file.path.dropFirst(basePath.count))
    }

    // MARK: - Swift source emission

    /// Produces the Swift source for `EmbeddedTemplates.swift`.
    ///
    /// Layout: `enum EmbeddedTemplates { struct Template; static let all: [Template]; lookup; availableNames }`.
    /// File contents are emitted as `#"""..."""#` raw-string literals with
    /// the closing `"""#` at column 0 — Swift then strips zero indentation,
    /// preserving each file's contents byte-for-byte. The leading `\n` after
    /// `#"""` and the trailing `\n` before `"""#` are stripped by Swift's
    /// multi-line rules, which is why we wrap as `\n{contents}\n`: the file
    /// contents already end in `\n`, and that final `\n` is preserved (it's
    /// the `\n` after that — the one we emit — that gets stripped).
    static func swiftSource(examplesRoot: URL) throws -> String {
        let templates = try collect(examplesRoot: examplesRoot)

        var out = """
        // GENERATED FILE — do not edit.
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

        for t in templates {
            out += "        Template(\n"
            out += "            name: \"\(t.name)\",\n"
            out += "            files: [\n"
            for (path, contents) in t.files {
                out += "                \"\(path)\": #\"\"\"\n\(contents)\n\"\"\"#,\n"
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

        return out
    }
}
