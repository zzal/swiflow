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
}
