import Testing
import Foundation
@testable import SwiflowColor

@Suite("APCA")
struct ApcaTests {
    // APCA-W3 reference Lc values (within rounding tolerance).
    @Test("Known APCA-W3 reference pairs") func referencePairs() {
        #expect(abs(Color.apcaContrast(textHex: "#000000", bgHex: "#ffffff") - 106.04) < 0.1)
        #expect(abs(Color.apcaContrast(textHex: "#ffffff", bgHex: "#000000") - -107.88) < 0.1)
        #expect(abs(Color.apcaContrast(textHex: "#888888", bgHex: "#ffffff") - 63.1) < 0.5)
    }

    @Test("Polarity flips sign when text/background swap") func polaritySign() {
        let darkOnLight = Color.apcaContrast(textHex: "#000000", bgHex: "#ffffff")
        let lightOnDark = Color.apcaContrast(textHex: "#ffffff", bgHex: "#000000")
        #expect(darkOnLight > 0)   // dark text on light bg → positive
        #expect(lightOnDark < 0)   // light text on dark bg → negative
    }

    @Test("Identical colors have ~zero contrast") func identicalIsZero() {
        #expect(Color.apcaContrast(textHex: "#7c3aed", bgHex: "#7c3aed") == 0)
    }

    @Test("recommendedLc maps text→75, non-text→45") func recommendedLcMapping() {
        #expect(Color.recommendedLc(isText: true) == 75)
        #expect(Color.recommendedLc(isText: false) == 45)
    }

    @Test("PaletteFailure.description appends the APCA clause after the WCAG part") func descriptionShowsApca() {
        let f = Color.PaletteFailure(token: "--x", mode: "light", ratio: 3.9, target: 4.5,
                                     apcaLc: 68, apcaTarget: 75)
        #expect(f.description.contains("3.90:1 < 4.5:1 required"))  // WCAG portion unchanged
        #expect(f.description.contains("APCA Lc 68"))
        #expect(f.description.contains("≥ 75 for text"))
    }

    @Test("A failing danger seed's diagnostic carries an APCA text target (75)") func dangerFailureCarriesApca() {
        let fails = Color.validateStatusFamily(name: "--sw-danger",
                                               lightHex: "#f1a9a9", darkHex: "#f1a9a9", rawBar: 4.5)
        let raw = fails.first { $0.token == "--sw-danger" && $0.mode == "light" }
        #expect(raw != nil)
        if let d = raw {
            #expect(d.apcaTarget == 75)
            #expect(abs(d.apcaLc) > 0)
            #expect(d.description.contains("required"))
            #expect(d.description.contains("APCA Lc"))
        }
    }

    @Test("A failing non-text success seed recommends the Lc 45 UI target") func successFailureTarget45() {
        let fails = Color.validateStatusFamily(name: "--sw-success",
                                               lightHex: "#bfe9cb", darkHex: "#bfe9cb", rawBar: 3.0)
        let raw = fails.first { $0.token == "--sw-success" && $0.mode == "light" }
        #expect(raw?.apcaTarget == 45)
    }

    @Test("A clean palette still produces no failures (no output regression)") func cleanPaletteNoFailures() {
        #expect(Color.validateAccentFamily(lightAccentHex: "#3b82f6", darkAccentHex: "#60a5fa").isEmpty)
    }
}
