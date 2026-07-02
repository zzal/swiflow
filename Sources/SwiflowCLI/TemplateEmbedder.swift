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

enum TemplateEmbedderError: Error, CustomStringConvertible {
    case missingTrailingNewline(URL)

    var description: String {
        switch self {
        case .missingTrailingNewline(let url):
            return "example file does not end with a newline: \(url.path) — add a trailing \\n so the codegen round-trip stays exact"
        }
    }
}

enum TemplateEmbedder {

    /// File / directory names excluded from every template.
    /// - `.build`, `.swiftpm`, `Package.resolved`, `.DS_Store`: build artifacts,
    ///   SwiftPM/Xcode user-state directories, and OS files.
    /// - `swiflow-driver.js`, `swiflow-service-worker.js`, `swiflow-manifest.json`:
    ///   the JS driver + service worker come from EmbeddedDriver (which is
    ///   itself codegen'd from js-driver/). Keeping them out of the template
    ///   avoids two paths for the same canonical bytes.
    /// - `RegionDemo`: a repo feature-demo (its wasm guest builds from source
    ///   via js-driver's asc), not a `swiflow init` starter — and it carries a
    ///   binary `universe.wasm` that can't round-trip this UTF-8 templating.
    static let blacklist: Set<String> = [
        ".build",
        ".swiftpm",
        ".DS_Store",
        "Package.resolved",
        "swiflow-driver.js",
        "swiflow-service-worker.js",
        "swiflow-manifest.json",
        "RegionDemo",
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
        // Guard: {{NAME}} must never land in Swift DECLARATION position — the
        // user's project name is a directory name (hyphens legal), not a Swift
        // identifier, so `final class {{NAME}}` scaffolds broken code (a real
        // user hit `final class my-swiflow`). Example root types must use
        // neutral names (Counter, QueryRoot, FetchRoot, ...).
        precondition(
            out.range(of: #"(class|struct|enum|protocol|actor|func|var|let)\s+\{\{NAME\}\}"#,
                      options: .regularExpression) == nil,
            "template '\(exampleName)' uses its own name as a Swift declaration — rename the type (see the guard comment)"
        )
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
            guard raw.hasSuffix("\n") else {
                throw TemplateEmbedderError.missingTrailingNewline(url)
            }
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
    /// File contents are emitted as `##"""..."""##` raw-string literals with
    /// the closing `"""##` at column 0 — Swift then strips zero indentation,
    /// preserving each file's contents byte-for-byte. Two hashes are used
    /// because the example files are Swift source and commonly contain
    /// one-hash raw-string literals (`#"""..."""#`); using a one-hash wrapper
    /// would prematurely close the generated literal, silently truncating the
    /// embedded contents. `##"""..."""##` is safe as long as no example file
    /// contains `"""##`, which is enforced by inspection. The leading `\n`
    /// after `##"""` and the trailing `\n` before `"""##` are stripped by
    /// Swift's multi-line rules, which is why we wrap as `\n{contents}\n`:
    /// the file contents already end in `\n`, and that final `\n` is
    /// preserved (it's the `\n` after that — the one we emit — that gets
    /// stripped). `collectFiles` enforces the trailing-newline invariant.
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

        return out
    }
}
