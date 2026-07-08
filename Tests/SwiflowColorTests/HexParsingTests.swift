// Tests/SwiflowColorTests/HexParsingTests.swift
//
// Audit V Wave-1: `Color.hex`'s documented contract is trap-on-malformed
// (gate user input through `normalizeHex` first) — but a 3-digit shorthand
// like "f00" did NOT trap: `UInt32("f00", radix: 16)` succeeds as 0x000f00,
// feeding a silently WRONG color into the contrast math the generator then
// blesses. The precondition now enforces exactly-6 digits so the contract
// is kept loudly.
import Testing
@testable import SwiflowColor

@Suite("Color.hex parsing")
struct HexParsingTests {

    @Test("6-digit forms parse, with and without '#', any case")
    func validForms() {
        let red = Color.hex("#ff0000")
        #expect(abs(red.r - 1.0) < 1e-9 && red.g == 0 && red.b == 0)
        let same = Color.hex("FF0000")
        #expect(abs(same.r - red.r) < 1e-9)
    }

    @Test("normalizeHex expands 3-digit shorthand to the 6-digit form hex() requires")
    func normalizeExpandsShorthand() throws {
        let full = try Color.normalizeHex("#f00")
        #expect(full == "#ff0000")
        let parsed = Color.hex(full)
        #expect(abs(parsed.r - 1.0) < 1e-9)
    }

    @Test("3-digit shorthand passed RAW traps instead of silently parsing as the wrong color",
          .enabled(if: exitTestsSupported))
    func shorthandTraps() async {
        await #expect(processExitsWith: .failure) {
            _ = Color.hex("f00")   // used to parse as 0x000f00 — near-black, not red
        }
    }

    @Test("non-hex input traps with the contract intact",
          .enabled(if: exitTestsSupported))
    func garbageTraps() async {
        await #expect(processExitsWith: .failure) {
            _ = Color.hex("nothex")
        }
    }
}

/// Exit tests need process spawning — mirror the gating used by the
/// Swiflow diagnostics exit tests (macOS/Linux hosts have it; keep the
/// guard so any future constrained environment skips rather than fails).
private var exitTestsSupported: Bool {
    #if os(macOS) || os(Linux)
    return true
    #else
    return false
    #endif
}
