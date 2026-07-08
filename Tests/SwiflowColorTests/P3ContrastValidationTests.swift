// Tests/SwiflowColorTests/P3ContrastValidationTests.swift
//
// Audit V Wave-2 #1: the P3 contrast validation gap. The generator emitted
// gamut-edge-widened oklch() lines validated ONLY via their hex fallbacks,
// under the claim "same L/H → same luminance/contrast" — color-science
// wrong (WCAG luminance is photometric Y, not OKLCH perceptual L; chroma
// widening shifts Y). Policy (user-selected): widen-then-back-off — emit
// the largest chroma that both fits P3 and keeps every family check at
// its bar.
import Testing
import Foundation
@testable import SwiflowColor

@Suite("P3 plumbing")
struct P3PlumbingTests {

    @Test("linP3ToLinRGB inverts linRGBToLinP3 (round-trip pin)")
    func matrixRoundTrip() {
        for hexStr in ["#7c3aed", "#e11d48", "#16a34a", "#ffffff", "#0b1220"] {
            let c = Color.hex(hexStr)
            let back = Color.linP3ToLinRGB(Color.linRGBToLinP3(c))
            #expect(abs(back.r - c.r) < 1e-5 && abs(back.g - c.g) < 1e-5 && abs(back.b - c.b) < 1e-5,
                    "\(hexStr) failed the round trip")
        }
    }

    @Test("clampGamutP3 is identity inside P3 and clamps an out-of-P3 color into it")
    func clampP3() {
        let inside = Color.hex("#7c3aed")
        let clamped = Color.clampGamutP3(inside)
        #expect(abs(clamped.r - inside.r) < 1e-6, "in-gamut color untouched")

        // Chroma pushed past the P3 edge → out of gamut → clamp brings it in.
        let lch = Color.okLabToOKLCH(Color.linRGBToOKLab(inside))
        let beyond = Color.okLabToLinRGB(Color.okLCHToOKLab(.init(L: lch.L, C: lch.C + 0.08, H: lch.H)))
        #expect(!Color.inP3Gamut(Color.linRGBToOKLab(beyond)))
        let fixedUp = Color.clampGamutP3(beyond)
        #expect(Color.inP3Gamut(Color.linRGBToOKLab(fixedUp)))
    }
}

@Suite("P3 widening — the falsity pin and the back-off")
struct P3WideningTests {

    /// The unclamped color a P3 display renders for a gamut-edge widening.
    private func widened(_ hexStr: String) -> LinRGB {
        let lch = Color.okLabToOKLCH(Color.linRGBToOKLab(Color.hex(hexStr)))
        let edge = Color.p3MaxChroma(L: lch.L, H: lch.H)
        return Color.okLabToLinRGB(Color.okLCHToOKLab(.init(L: lch.L, C: edge, H: lch.H)))
    }

    @Test("FALSITY PIN: gamut-edge widening at constant L/H SHIFTS WCAG contrast")
    func wideningShiftsContrast() {
        // The old comment claimed same L/H → same contrast. Measure it.
        let surface = Color.hex("#ffffff")
        let seed = Color.hex("#e11d48")   // vivid red — real widening headroom
        let rHex = Color.wcagContrast(seed, surface)
        let rWide = Color.wcagContrast(widened("#e11d48"), surface)
        #expect(abs(rHex - rWide) > 0.01,
                "widening changed the ratio (\(rHex) vs \(rWide)) — validating hex alone blesses a different color")
    }

    @Test("safe widening emits the FULL gamut edge when every check passes there")
    func tameSeedsWidenFully() {
        let lch = Color.okLabToOKLCH(Color.linRGBToOKLab(Color.hex("#3b82f6")))
        let edge = Color.p3MaxChroma(L: lch.L, H: lch.H)
        let s = Color.safeP3OKLCHString(fromHex: "#3b82f6", checks: { _ in true })
        let c = Double(s.dropFirst(6).dropLast().split(separator: " ")[1])!
        #expect(abs(c - edge) < 0.001, "always-passing checks → no vividness sacrificed")
    }

    @Test("safe widening degrades to the seed's own chroma when nothing wider passes")
    func floorIsSeedChroma() {
        let lch = Color.okLabToOKLCH(Color.linRGBToOKLab(Color.hex("#e11d48")))
        // Nothing passes → the fallback emits exactly the seed's chroma
        // (no widening; the sRGB verdict is the P3 verdict).
        let s = Color.safeP3OKLCHString(fromHex: "#e11d48", checks: { _ in false })
        let c = Double(s.dropFirst(6).dropLast().split(separator: " ")[1])!
        #expect(abs(c - lch.C) < 0.001, "floor = the sRGB seed's chroma — never below")
    }

    @Test("safe widening emits well-formed oklch(L C Hdeg)")
    func stringForm() {
        let s = Color.safeP3OKLCHString(fromHex: "#7c3aed", checks: { _ in true })
        #expect(s.hasPrefix("oklch(") && s.hasSuffix(")"))
        let nums = s.dropFirst(6).dropLast().split(separator: " ").compactMap { Double($0) }
        #expect(nums.count == 3)
        #expect(nums[0] > 0 && nums[0] < 1)
        #expect(nums[2] >= 0 && nums[2] <= 360)
    }
}
