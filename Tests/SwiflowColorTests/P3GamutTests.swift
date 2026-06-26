import Testing
import Foundation
@testable import SwiflowColor

@Suite("P3Gamut")
struct P3GamutTests {
    @Test("a saturated sRGB color is inside the P3 gamut") func srgbInsideP3() {
        // Any in-sRGB color is in P3 (P3 ⊇ sRGB).
        for hex in ["#7c3aed", "#e11d48", "#16a34a", "#0284c7", "#b45309"] {
            #expect(Color.inP3Gamut(Color.linRGBToOKLab(Color.hex(hex))))
        }
    }

    @Test("chroma boosted past the P3 edge falls outside the gamut") func beyondEdgeOutside() {
        let lch = Color.okLabToOKLCH(Color.linRGBToOKLab(Color.hex("#7c3aed")))
        let edge = Color.p3MaxChroma(L: lch.L, H: lch.H)
        #expect(Color.inP3Gamut(Color.okLCHToOKLab(.init(L: lch.L, C: edge, H: lch.H))))
        // a hair past the edge is out of gamut
        #expect(!Color.inP3Gamut(Color.okLCHToOKLab(.init(L: lch.L, C: edge + 0.02, H: lch.H))))
    }

    @Test("P3 edge chroma is >= the seed's sRGB chroma (only widens)") func boostWidens() {
        for hex in ["#7c3aed", "#e11d48", "#0284c7"] {
            let lch = Color.okLabToOKLCH(Color.linRGBToOKLab(Color.hex(hex)))
            #expect(Color.p3MaxChroma(L: lch.L, H: lch.H) >= lch.C - 1e-9)
        }
        // for a vivid violet the P3 edge is strictly wider
        let v = Color.okLabToOKLCH(Color.linRGBToOKLab(Color.hex("#7c3aed")))
        #expect(Color.p3MaxChroma(L: v.L, H: v.H) > v.C + 1e-3)
    }

    @Test("p3OKLCHString is well-formed oklch() with hue in 0...360 degrees") func stringForm() {
        let s = Color.p3OKLCHString(fromHex: "#7c3aed")
        #expect(s.hasPrefix("oklch(") && s.hasSuffix(")"))
        // oklch(<L> <C> <Hdeg>)
        let nums = s.dropFirst(6).dropLast()
            .split(separator: " ").compactMap { Double($0) }
        #expect(nums.count == 3)
        #expect(nums[0] > 0 && nums[0] < 1)        // L in 0..1
        #expect(nums[2] >= 0 && nums[2] <= 360)     // H in degrees
    }
}
