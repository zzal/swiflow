import Testing
import Foundation
import SwiflowColor   // plain — exercises ONLY the public API

@Suite("PublicAPI")
struct PublicAPITests {
    @Test("generate returns valid CSS for a good seed") func goodSeed() throws {
        let r = try ThemeGenerator.generate(.init(primary: "#3b82f6"))
        #expect(r.isValid)
        #expect(r.failures.isEmpty)
        #expect(r.css.contains("--sw-accent: light-dark(#3b82f6, #"))
    }

    @Test("generate returns failures (not a throw) for a washed-out seed") func failingSeed() throws {
        let r = try ThemeGenerator.generate(.init(primary: "#3b82f6", danger: "#f1a9a9"))
        #expect(!r.isValid)
        #expect(r.failures.contains { $0.token == "--sw-danger" })
        // advisory APCA reading rides along on each failure
        #expect(r.failures.allSatisfy { $0.apcaTarget == 75 || $0.apcaTarget == 45 })
    }

    @Test("generate throws invalidHex on malformed input") func invalidHex() {
        #expect(throws: ThemeError.self) {
            _ = try ThemeGenerator.generate(.init(primary: "#nope"))
        }
    }

    @Test("generate accepts an oklch() primary seed") func oklchSeed() throws {
        let r = try ThemeGenerator.generate(.init(primary: "oklch(0.62 0.17 255)"))
        #expect(r.css.contains("--sw-accent: light-dark(#"))
    }

    @Test("generate throws invalidColor on a malformed oklch()") func invalidOklch() {
        #expect(throws: ThemeError.self) {
            _ = try ThemeGenerator.generate(.init(primary: "oklch(nope)"))
        }
    }

    @Test("Contrast metrics work from hex and oklch") func contrastMetrics() throws {
        #expect(abs(try Contrast.wcag("#000000", "#ffffff") - 21.0) < 0.1)
        #expect(abs(try Contrast.apca(text: "#000000", bg: "#ffffff") - 106.04) < 0.1)
        // achromatic-extreme oklch resolves to the same black/white → same 21:1
        #expect(abs(try Contrast.wcag("oklch(0 0 0)", "oklch(1 0 0)") - 21.0) < 0.1)
        #expect(throws: ThemeError.self) { _ = try Contrast.wcag("zzz", "#fff") }
    }
}
