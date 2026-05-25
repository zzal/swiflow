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

    @Test("Package.swift renders identically to examples/HelloWorld/Package.swift")
    func packageSwiftMatchesExample() throws {
        let rendered = Templates.packageSwift(name: "HelloWorld", swiflowDep: .path("../.."))
        let expected = try Self.exampleFile("Package.swift")
        #expect(rendered == expected)
    }

    @Test("Sources/App/App.swift renders identically to the example")
    func appSwiftMatchesExample() throws {
        let rendered = Templates.appSwift(name: "HelloWorld")
        let expected = try Self.exampleFile("Sources/App/App.swift")
        #expect(rendered == expected)
    }

    @Test("index.html renders identically to the example")
    func indexHTMLMatchesExample() throws {
        let rendered = Templates.indexHTML(name: "HelloWorld")
        let expected = try Self.exampleFile("index.html")
        #expect(rendered == expected)
    }

    @Test(".gitignore renders identically to the example")
    func gitignoreMatchesExample() throws {
        let rendered = Templates.gitignore()
        let expected = try Self.exampleFile(".gitignore")
        #expect(rendered == expected)
    }

    @Test("README.md renders identically to examples/HelloWorld/README.md")
    func readmeMatchesExample() throws {
        let rendered = Templates.readme(name: "HelloWorld")
        let expected = try Self.exampleFile("README.md")
        #expect(rendered == expected)
    }

    @Test("README is non-empty and mentions both swiflow build and the static server")
    func readmeMentionsKeyCommands() {
        let rendered = Templates.readme(name: "HelloWorld")
        #expect(rendered.contains("swiflow build"))
        #expect(rendered.contains("python3 -m http.server"))
        #expect(rendered.contains("HelloWorld"))
    }

    @Test("Variable substitution applies {{NAME}} everywhere it appears")
    func substitutesName() {
        let rendered = Templates.packageSwift(name: "MyCoolApp", swiflowDep: .path("../.."))
        #expect(rendered.contains("\"MyCoolApp\""))
        #expect(!rendered.contains("{{NAME}}"))
    }

    @Test("Variable substitution applies {{SWIFLOW_SOURCE}}")
    func substitutesSwiflowSource() {
        let rendered = Templates.packageSwift(name: "Demo", swiflowDep: .path("/tmp/swiflow-checkout"))
        #expect(rendered.contains("/tmp/swiflow-checkout"))
        #expect(!rendered.contains("{{SWIFLOW_SOURCE}}"))
    }

    @Test("index.html title substitutes {{NAME}}")
    func indexHTMLTitleSubstitutesName() {
        let rendered = Templates.indexHTML(name: "MyCoolApp")
        #expect(rendered.contains("<title>MyCoolApp</title>"))
        #expect(!rendered.contains("Swiflow Hello World"))
        #expect(!rendered.contains("{{NAME}}"))
    }

    @Test("packageSwift with URL dep uses .package(url:exact:) instead of .package(path:)")
    func packageSwiftURLDep() {
        let pkg = Templates.packageSwift(
            name: "MyApp",
            swiflowDep: .url("https://github.com/example/Swiflow.git", version: "1.0.0")
        )
        #expect(pkg.contains(#".package(url: "https://github.com/example/Swiflow.git", exact: "1.0.0")"#))
        #expect(!pkg.contains(".package(path:"))
        #expect(!pkg.contains("{{SWIFLOW_SOURCE}}"),
                "Placeholder must be substituted; if not, the template's .package(path:) literal changed.")
    }

    @Test("packageSwift with path dep uses .package(path:)")
    func packageSwiftPathDep() {
        let pkg = Templates.packageSwift(
            name: "MyApp",
            swiflowDep: .path("/abs/path/to/swiflow")
        )
        #expect(pkg.contains(#".package(path: "/abs/path/to/swiflow")"#))
        // The template also contains a JavaScriptKit .package(url:…) dependency,
        // so we only assert the Swiflow-specific URL form is absent.
        #expect(!pkg.contains(#".package(url: "https://github.com/swiflow/"#))
        #expect(!pkg.contains("{{SWIFLOW_SOURCE}}"),
                "Placeholder must be substituted; if not, the template's .package(path:) literal changed.")
    }
}
