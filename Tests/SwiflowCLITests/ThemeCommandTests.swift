import Testing
import Foundation
@testable import SwiflowCLI

@Suite("ThemeCommand")
struct ThemeCommandTests {
    @Test("--primary with a good color writes the override to --out and exits zero")
    func writesFile() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("sw-theme-\(UUID().uuidString).css")
        defer { try? FileManager.default.removeItem(at: tmp) }
        var cmd = try ThemeCommand.parse(["--primary", "#3b82f6", "--out", tmp.path])
        try cmd.run()
        let css = try String(contentsOf: tmp, encoding: .utf8)
        #expect(css.contains("--sw-accent: light-dark(#3b82f6, #"))
    }

    @Test("a washed-out --primary makes run() throw (nonzero exit)")
    func badColorThrows() throws {
        var cmd = try ThemeCommand.parse(["--primary", "#fde047"])
        #expect(throws: (any Error).self) { try cmd.run() }
    }

    @Test("missing --primary is a parse error")
    func missingPrimary() {
        #expect(throws: (any Error).self) { _ = try ThemeCommand.parse([]) }
    }

    @Test("--neutrals writes the full palette (neutral tokens + prefers-contrast block)")
    func neutralsFlagWritesFullPalette() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("sw-theme-\(UUID().uuidString).css")
        defer { try? FileManager.default.removeItem(at: tmp) }
        var cmd = try ThemeCommand.parse(["--primary", "#7c3aed", "--neutrals", "--out", tmp.path])
        try cmd.run()
        let css = try String(contentsOf: tmp, encoding: .utf8)
        #expect(css.contains("--sw-surface: light-dark(#"))
        #expect(css.contains("@media (prefers-contrast: more)"))
    }

    @Test("Without --neutrals the output stays accent-only")
    func noNeutralsByDefault() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("sw-theme-\(UUID().uuidString).css")
        defer { try? FileManager.default.removeItem(at: tmp) }
        var cmd = try ThemeCommand.parse(["--primary", "#7c3aed", "--out", tmp.path])
        try cmd.run()
        let css = try String(contentsOf: tmp, encoding: .utf8)
        #expect(!css.contains("--sw-surface"))
    }
}
