// Tests/SwiflowCLITests/TemplatesTests.swift
//
// These tests are the load-bearing guarantee that `swiflow init` will
// produce a project byte-identical to examples/HelloWorld/ (which Phase 2a
// proved works end-to-end). Any drift between templates and the example
// is either an intentional template improvement (then update the example)
// or a regression (then fix the template).

import Foundation
import Testing
@testable import SwiflowCLI

@Suite("Init templates")
struct TemplatesTests {
    /// Repo root resolved relative to this test file's location.
    static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // SwiflowCLITests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
    }

    static func exampleFile(_ relativePath: String) throws -> String {
        let url = repoRoot
            .appendingPathComponent("examples/HelloWorld")
            .appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test("examples/HelloWorld/swiflow-driver.js byte-equals js-driver/swiflow-driver.js")
    func exampleDriverMatchesCanonical() throws {
        let canonical = try String(
            contentsOf: Self.repoRoot.appendingPathComponent("js-driver/swiflow-driver.js"),
            encoding: .utf8
        )
        let example = try Self.exampleFile("swiflow-driver.js")
        #expect(canonical == example,
                "examples/HelloWorld/swiflow-driver.js drifted from js-driver/swiflow-driver.js — `cp` the canonical file over the example")
    }

    @Test("examples/HelloWorld/swiflow-service-worker.js byte-equals js-driver/swiflow-service-worker.js")
    func exampleServiceWorkerMatchesCanonical() throws {
        let canonical = try String(
            contentsOf: Self.repoRoot.appendingPathComponent("js-driver/swiflow-service-worker.js"),
            encoding: .utf8
        )
        let example = try Self.exampleFile("swiflow-service-worker.js")
        #expect(canonical == example,
                "examples/HelloWorld/swiflow-service-worker.js drifted from js-driver/swiflow-service-worker.js — `cp` the canonical file over the example")
    }

    @Test("Every template renders byte-identical to its examples/<name>/ tree",
          arguments: ["HelloWorld", "MiniRouter"])
    func templateRoundTrip(name: String) throws {
        let template = try #require(EmbeddedTemplates.lookup(name),
                                    "EmbeddedTemplates.lookup(\(name)) returned nil")
        let exampleRoot = Self.repoRoot.appendingPathComponent("examples").appendingPathComponent(name)

        for (relativePath, raw) in template.files {
            let rendered = Templates.render(raw, name: name, swiflowDep: .path("../.."))
            let onDisk = try String(
                contentsOf: exampleRoot.appendingPathComponent(relativePath),
                encoding: .utf8
            )
            #expect(rendered == onDisk,
                    "drift in \(name)/\(relativePath); regenerate via `swift scripts/embed-templates.swift`")
        }
    }

    @Test("Every non-blacklisted file under examples/<name>/ appears in the corresponding template",
          arguments: ["HelloWorld", "MiniRouter"])
    func templateCoversAllOnDiskFiles(name: String) throws {
        let template = try #require(EmbeddedTemplates.lookup(name))
        let exampleRoot = Self.repoRoot.appendingPathComponent("examples").appendingPathComponent(name)

        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: exampleRoot, includingPropertiesForKeys: [.isDirectoryKey]) else {
            Issue.record("could not enumerate \(exampleRoot.path)"); return
        }

        var onDiskRelativePaths: Set<String> = []
        for case let url as URL in enumerator {
            let last = url.lastPathComponent
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if TemplateEmbedder.blacklist.contains(last) {
                if isDir { enumerator.skipDescendants() }
                continue
            }
            if isDir { continue }
            let basePath = exampleRoot.path + "/"
            onDiskRelativePaths.insert(String(url.path.dropFirst(basePath.count)))
        }

        let templatePaths = Set(template.files.keys)
        #expect(templatePaths == onDiskRelativePaths, """
            \(name) template files diverge from examples/\(name)/.
            Only-in-template: \(templatePaths.subtracting(onDiskRelativePaths))
            Only-on-disk:    \(onDiskRelativePaths.subtracting(templatePaths))
            Regenerate via `swift scripts/embed-templates.swift`.
            """)
    }

    @Test("render substitutes {{NAME}} and {{SWIFLOW_DEP}}")
    func renderSubstitutesBothTokens() {
        let raw = #"""
        name: "{{NAME}}", deps: [
            {{SWIFLOW_DEP}},
        ]
        """#
        let out = Templates.render(raw, name: "MyApp", swiflowDep: .path("/abs/swiflow"))
        #expect(out.contains(#"name: "MyApp""#))
        #expect(out.contains(#".package(path: "/abs/swiflow")"#))
        #expect(!out.contains("{{NAME}}"))
        #expect(!out.contains("{{SWIFLOW_DEP}}"))
    }

    @Test("render with URL dep produces .package(url:exact:)")
    func renderUrlDep() {
        let raw = "{{SWIFLOW_DEP}}"
        let out = Templates.render(raw, name: "Demo", swiflowDep: .url("https://example.com/repo.git", version: "1.2.3"))
        #expect(out == #".package(url: "https://example.com/repo.git", exact: "1.2.3")"#)
    }
}
