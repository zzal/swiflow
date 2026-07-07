// Tests/SwiflowCLITests/TemplateEmbedderTests.swift
import Foundation
import Testing
import SwiflowEmbedders
@testable import SwiflowCLI

@Suite("Template embedding")
struct TemplateEmbedderTests {

    // MARK: - normalize()

    @Test("normalize replaces literal example name with {{NAME}}")
    func normalizeReplacesName() {
        let raw = #"let package = Package(name: "MiniRouter", ...)"#
        let out = TemplateEmbedder.normalize(raw, exampleName: "MiniRouter", relativePath: "Package.swift")
        #expect(out.contains(#"name: "{{NAME}}""#))
        #expect(!out.contains("MiniRouter"))
    }

    @Test("normalize swaps .package(path: \"../..\") for {{SWIFLOW_DEP}} in Package.swift only")
    func normalizeSwapsSwiflowDep() {
        let pkg = #".package(path: "../..")"#
        let out = TemplateEmbedder.normalize(pkg, exampleName: "HelloWorld", relativePath: "Package.swift")
        #expect(out == "{{SWIFLOW_DEP}}")
    }

    @Test("normalize leaves .package(path: \"../..\") alone outside Package.swift")
    func normalizeSwiflowDepOnlyInPackage() {
        let txt = #"some docs mention .package(path: "../..") in prose"#
        let out = TemplateEmbedder.normalize(txt, exampleName: "HelloWorld", relativePath: "README.md")
        #expect(out.contains(#".package(path: "../..")"#),
                "non-Package.swift files keep the literal — SWIFLOW_DEP is Package.swift-only")
    }

    @Test("collectFiles throws if an example file lacks a trailing newline")
    func collectFilesRejectsNoTrailingNewline() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("template-embedder-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let bad = tmp.appendingPathComponent("no-newline.txt")
        try "no trailing newline here".write(to: bad, atomically: true, encoding: .utf8)

        #expect(throws: TemplateEmbedderError.self) {
            _ = try TemplateEmbedder.collectFiles(in: tmp, exampleName: "Tmp")
        }
    }

    @Test("swiftSource handles file contents containing #\"\"\" without truncation")
    func swiftSourceTolerantOfRawStringDelimiters() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("template-embedder-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let example = tmp.appendingPathComponent("Spicy")
        try FileManager.default.createDirectory(at: example, withIntermediateDirectories: true)
        // A file whose contents contain the one-hash raw-string delimiters that
        // the old emission strategy would have closed prematurely.
        let trickyContents = "let s = #\"\"\"\nhello\n\"\"\"#\n"
        try trickyContents.write(
            to: example.appendingPathComponent("File.swift"),
            atomically: true, encoding: .utf8
        )

        let generated = try TemplateEmbedder.swiftSource(examplesRoot: tmp)
        // The generated source must contain the contents intact — the two-hash
        // wrapper survives the one-hash collision.
        #expect(generated.contains(trickyContents))
    }
}

extension TemplateEmbedderTests {

    /// Repo root resolved relative to this test file's location.
    static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // SwiflowCLITests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
    }

    @Test("EmbeddedTemplates.swift is bit-for-bit what TemplateEmbedder would produce")
    func embeddedTemplatesIsFresh() throws {
        let examplesRoot = Self.repoRoot.appendingPathComponent("examples")
        let embeddedURL = Self.repoRoot.appendingPathComponent("Sources/SwiflowCLI/EmbeddedTemplates.swift")

        let expected = try TemplateEmbedder.swiftSource(examplesRoot: examplesRoot)
        let actual = try String(contentsOf: embeddedURL, encoding: .utf8)

        #expect(actual == expected, """
            EmbeddedTemplates.swift drifted from TemplateEmbedder.swiftSource output. \
            Regenerate by running, from the repo root:
                swift run swiflow-codegen templates
            then commit Sources/SwiflowCLI/EmbeddedTemplates.swift.
            """)
    }

    @Test("EmbeddedTemplates.all is non-empty and contains HelloWorld")
    func embeddedTemplatesContainsHelloWorld() {
        #expect(!EmbeddedTemplates.all.isEmpty)
        #expect(EmbeddedTemplates.availableNames.contains("HelloWorld"))
    }

    @Test("EmbeddedTemplates.lookup returns nil for an unknown name")
    func embeddedTemplatesLookupMissing() {
        #expect(EmbeddedTemplates.lookup("DoesNotExist") == nil)
    }

    @Test("HelloWorld template contains Package.swift, App.swift, index.html, README, .gitignore")
    func helloWorldTemplateShape() throws {
        let t = try #require(EmbeddedTemplates.lookup("HelloWorld"))
        #expect(t.files["Package.swift"] != nil)
        #expect(t.files["Sources/App/App.swift"] != nil)
        #expect(t.files["index.html"] != nil)
        #expect(t.files[".gitignore"] != nil)
        #expect(t.files["README.md"] != nil)
        // Driver / SW must NOT be in the template — they come from EmbeddedDriver.
        #expect(t.files["swiflow-driver.js"] == nil)
        #expect(t.files["swiflow-service-worker.js"] == nil)
    }

    @Test("Package.swift template uses {{NAME}} and {{SWIFLOW_DEP}} placeholders")
    func helloWorldPackageSwiftPlaceholders() throws {
        let t = try #require(EmbeddedTemplates.lookup("HelloWorld"))
        let pkg = try #require(t.files["Package.swift"])
        #expect(pkg.contains(#"name: "{{NAME}}""#))
        #expect(pkg.contains("{{SWIFLOW_DEP}}"))
        #expect(!pkg.contains("HelloWorld"))
        #expect(!pkg.contains(#".package(path: "../..")"#))
    }
}

// Regression gate for the my-swiflow scaffold bug: a project name is a
// DIRECTORY name (hyphens legal), not a Swift identifier — so no embedded
// template may put {{NAME}} in Swift declaration position. (The embedder and
// the codegen script both precondition on this; this test is the in-suite
// witness.) A user hit `final class my-swiflow` via the QueryDemo template.
@Suite("Embedded templates — {{NAME}} placement")
struct TemplateNamePlacementTests {
    @Test("no template uses {{NAME}} as a Swift declaration name")
    func noDeclarationPositionName() {
        for template in EmbeddedTemplates.all {
            for (path, contents) in template.files where path.hasSuffix(".swift") {
                #expect(contents.range(
                    of: #"(class|struct|enum|protocol|actor|func|var|let)\s+\{\{NAME\}\}"#,
                    options: .regularExpression) == nil,
                    "template \(template.name), file \(path): {{NAME}} in declaration position")
            }
        }
    }
}
