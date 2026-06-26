import Testing
import Foundation
@testable import SwiflowColor

@Suite("StatusSeed")
struct StatusSeedTests {
    // Derive the dark arm the same way the generator does.
    private func dark(_ light: String) -> String { Color.darkAccent(from: light) }

    @Test("Shipped default danger/success seeds validate clean at their per-usage bars")
    func defaultsPass() {
        // #dc2626 raw on white = 4.83 (≥4.5 error-text bar); #16a34a raw = 3.30 (≥3.0 UI bar).
        // -strong derivations (L 0.40/0.80, 0.30/0.88) clear 4.5/7 with large margin for vivid hues.
        #expect(Color.validateStatusFamily(name: "--sw-danger",
                                           lightHex: "#dc2626", darkHex: dark("#dc2626"),
                                           rawBar: 4.5).isEmpty)
        #expect(Color.validateStatusFamily(name: "--sw-success",
                                           lightHex: "#16a34a", darkHex: dark("#16a34a"),
                                           rawBar: 3.0).isEmpty)
    }

    @Test("Example brand seeds (rose danger, emerald success) validate clean")
    func exampleSeedsPass() {
        #expect(Color.validateStatusFamily(name: "--sw-danger",
                                           lightHex: "#e11d48", darkHex: dark("#e11d48"),
                                           rawBar: 4.5).isEmpty)
        #expect(Color.validateStatusFamily(name: "--sw-success",
                                           lightHex: "#059669", darkHex: dark("#059669"),
                                           rawBar: 3.0).isEmpty)
    }

    @Test("A washed-out danger fails the raw 4.5 error-text bar, naming --sw-danger")
    func washedDangerFiresRawBar() {
        // #f5a3a3 light pink: ~2:1 on white, below the 4.5 raw error-text bar.
        let fails = Color.validateStatusFamily(name: "--sw-danger",
                                               lightHex: "#f5a3a3", darkHex: dark("#f5a3a3"),
                                               rawBar: 4.5)
        #expect(!fails.isEmpty)
        #expect(fails.contains { $0.token == "--sw-danger" && $0.mode == "light" })
        #expect(fails.allSatisfy { $0.ratio < $0.target })
    }

    @Test("A too-light success fails the raw 3:1 UI bar, naming --sw-success")
    func lightSuccessFiresRawBar() {
        // #86efac light green: ~1.5:1 on white, below the 3.0 raw UI/border bar.
        let fails = Color.validateStatusFamily(name: "--sw-success",
                                               lightHex: "#86efac", darkHex: dark("#86efac"),
                                               rawBar: 3.0)
        #expect(fails.contains { $0.token == "--sw-success" && $0.mode == "light" })
    }
}
