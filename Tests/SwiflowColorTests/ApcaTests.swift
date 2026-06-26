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
}
