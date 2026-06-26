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

    @Test("Contrast metrics work from hex") func contrastMetrics() throws {
        #expect(abs(try Contrast.wcag("#000000", "#ffffff") - 21.0) < 0.1)
        #expect(abs(try Contrast.apca(textHex: "#000000", bgHex: "#ffffff") - 106.04) < 0.1)
        #expect(throws: ThemeError.self) { _ = try Contrast.wcag("zzz", "#fff") }
    }
}
