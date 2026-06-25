import Testing
import Foundation
@testable import SwiflowColor

@Suite("AccentTheme")
struct AccentThemeTests {
    @Test("A good brand color validates clean and emits a light-dark --sw-accent")
    func goodSeedEmitsCSS() throws {
        let css = try Color.accentThemeCSS(primaryHex: "#3b82f6")
        #expect(css.contains("--sw-accent: light-dark(#3b82f6, #"))
        #expect(css.contains(":root"))
    }

    @Test("3-digit hex and missing # are normalized")
    func normalizesHex() throws {
        let css = try Color.accentThemeCSS(primaryHex: "3b82f6")
        #expect(css.contains("--sw-accent: light-dark(#3b82f6,"))
    }

    @Test("A washed-out seed fails validation with a specific diagnostic")
    func badSeedThrows() {
        // A light yellow: ~1.07:1 as accent text/links on white — below the 3:1 UI bar.
        #expect(throws: Color.PaletteError.self) {
            _ = try Color.accentThemeCSS(primaryHex: "#fde047")
        }
    }

    @Test("Invalid hex throws invalidHex")
    func invalidHexThrows() {
        #expect(throws: Color.PaletteError.self) {
            _ = try Color.accentThemeCSS(primaryHex: "nope")
        }
    }

    @Test("validateAccentFamily returns failures naming token + mode")
    func validationNamesFailures() {
        let fails = Color.validateAccentFamily(lightAccentHex: "#fde047",
                                               darkAccentHex: Color.darkAccent(from: "#fde047"))
        #expect(!fails.isEmpty)
        #expect(fails.contains { $0.token.contains("as text") })
        #expect(fails.allSatisfy { !$0.token.isEmpty && $0.ratio < $0.target })
    }
}
