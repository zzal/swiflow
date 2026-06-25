import Testing
import Foundation
@testable import SwiflowColor

@Suite("DarkAccent")
struct DarkAccentTests {
    @Test("darkAccent lightens and slightly desaturates the seed, preserving hue")
    func derivesLighterDarkArm() {
        let seed = "#3b82f6"
        let darkHex = Color.darkAccent(from: seed)
        let seedLCH = Color.okLabToOKLCH(Color.linRGBToOKLab(Color.hex(seed)))
        let darkLCH = Color.okLabToOKLCH(Color.linRGBToOKLab(Color.hex(darkHex)))
        // Lighter (clamped into the dark-mode band), less chroma, same hue.
        #expect(darkLCH.L > seedLCH.L)
        #expect(darkLCH.L >= 0.68 && darkLCH.L <= 0.76)
        #expect(darkLCH.C < seedLCH.C)
        #expect(abs(darkLCH.H - seedLCH.H) < 0.02)
        // Higher luminance than the seed (reads on a dark surface).
        #expect(Color.hex(darkHex).luminance > Color.hex(seed).luminance)
    }

    @Test("darkAccent returns a well-formed #rrggbb")
    func wellFormedHex() {
        let h = Color.darkAccent(from: "#7c3aed")
        #expect(h.count == 7 && h.hasPrefix("#"))
        #expect(h.dropFirst().allSatisfy { "0123456789abcdef".contains($0) })
    }
}
