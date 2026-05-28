// Tests/SwiflowCLITests/TemplateEmbedderTests.swift
import Foundation
import Testing
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
