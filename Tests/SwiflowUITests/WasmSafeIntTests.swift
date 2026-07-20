// Tests/SwiflowUITests/WasmSafeIntTests.swift
//
// The Double→Int gate both cssPixelInt and formatControlNumber funnel
// through. Boundaries are pinned here on the host, where Int is 64-bit — the
// point is that these results are IDENTICAL on wasm32's 32-bit Int (no trap),
// so the host suite is a faithful stand-in.
import Testing
@testable import SwiflowUI

@Suite("WasmSafeInt")
struct WasmSafeIntTests {

    @Test("exact accepts the full signed-32-bit range, inclusive of both ends")
    func exactInRange() {
        #expect(WasmSafeInt.exact(0) == 0)
        #expect(WasmSafeInt.exact(-5) == -5)
        #expect(WasmSafeInt.exact(2_147_483_647) == 2_147_483_647)   // Int32.max
        #expect(WasmSafeInt.exact(-2_147_483_648) == -2_147_483_648) // Int32.min — representable, trap-free
    }

    @Test("exact returns nil just past either end (where Int(_:) would trap on wasm32)")
    func exactOutOfRange() {
        #expect(WasmSafeInt.exact(2_147_483_648) == nil)    // Int32.max + 1
        #expect(WasmSafeInt.exact(-2_147_483_649) == nil)   // Int32.min − 1
        #expect(WasmSafeInt.exact(1e12) == nil)             // epoch-ms scale
    }

    @Test("exact rejects NaN and infinities via the range comparison")
    func exactNonFinite() {
        #expect(WasmSafeInt.exact(.nan) == nil)
        #expect(WasmSafeInt.exact(.infinity) == nil)
        #expect(WasmSafeInt.exact(-.infinity) == nil)
    }

    @Test("exact truncates a fractional value toward zero (caller decides whether that's wanted)")
    func exactTruncates() {
        #expect(WasmSafeInt.exact(41.9) == 41)
        #expect(WasmSafeInt.exact(-41.9) == -41)
    }

    @Test("pixelClamp floors to a non-negative Int and clamps the 32-bit ceiling")
    func pixelClamp() {
        #expect(WasmSafeInt.pixelClamp(0) == 0)
        #expect(WasmSafeInt.pixelClamp(41.9) == 41)          // floor
        #expect(WasmSafeInt.pixelClamp(-5) == 0)             // pixels are ≥ 0
        #expect(WasmSafeInt.pixelClamp(1e12) == 2_147_483_000)   // beyond 2^31 → clamp, never trap
        #expect(WasmSafeInt.pixelClamp(.infinity) == 2_147_483_000)
        #expect(WasmSafeInt.pixelClamp(.nan) == 0)
    }

    @Test("formatControlNumber integer-formats Int32.min now that exact accepts it")
    func formatBoundary() {
        #expect(formatControlNumber(-2_147_483_648) == "-2147483648")
        #expect(formatControlNumber(2_147_483_648) == String(2_147_483_648.0))   // still Double past the ceiling
    }
}
