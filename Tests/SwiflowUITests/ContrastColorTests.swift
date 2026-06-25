import Testing
import Foundation
@testable import SwiflowUI

@Suite("ContrastColor")
struct ContrastColorTests {
    @Test("Hex parses to linear sRGB with correct WCAG luminance")
    func luminanceEndpoints() {
        #expect(abs(Color.hex("#ffffff").luminance - 1.0) < 1e-9)
        #expect(abs(Color.hex("#000000").luminance - 0.0) < 1e-9)
    }

    @Test("WCAG contrast: white on black is 21:1; #767676 on white is ~4.54:1")
    func wcagKnownPairs() {
        #expect(abs(Color.wcagContrast(.white, .black) - 21.0) < 0.01)
        let midGrayOnWhite = Color.wcagContrast(Color.hex("#767676"), .white)
        #expect(abs(midGrayOnWhite - 4.54) < 0.05)
    }
}
