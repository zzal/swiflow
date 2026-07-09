// Tests/SwiflowUITests/DataTablePixelMathTests.swift
//
// Audit V Wave-3: DataTable's virtualization pixel math used `Int(_:)` on
// Doubles and raw Int multiplication — the wasm32-Int-is-32-bit trap class
// (the #154 clock trap's sibling): `Int(scrollTop)` traps past ±2^31 on
// wasm, and `rowCount * rowHeight` overflows. Host Int is 64-bit and HIDES
// both, so the fix is an extracted helper that clamps identically on every
// platform — host tests then pin the exact behavior wasm gets.
import Testing
@testable import Swiflow
@testable import SwiflowUI

private struct Person: Identifiable, Equatable { let id: Int; let name: String }

@Suite("DataTable pixel math — wasm32-safe")
@MainActor
struct DataTablePixelMathTests {

    @Test("cssPixelInt clamps the wasm32 trap range identically on every platform")
    func clampBehavior() {
        #expect(cssPixelInt(0) == 0)
        #expect(cssPixelInt(41.9) == 41)                 // floor
        #expect(cssPixelInt(-5) == 0)                    // scroll metrics are ≥ 0
        #expect(cssPixelInt(1e12) == 2_147_483_000)      // beyond 2^31 → clamp, never trap
        #expect(cssPixelInt(.infinity) == 2_147_483_000)
        #expect(cssPixelInt(.nan) == 0)
    }

    @Test("an absurd scrollTop clamps to the last row instead of trapping")
    func hugeScrollTopClamps() {
        let people = (0..<100).map { Person(id: $0, name: "P\($0)") }
        let box = makeDataTableBox(people, id: \.id, maxHeight: "300px",
                                   virtualization: .fixed(rowHeight: 40)) {
            Column("Name", value: \.name)
        }
        box.setViewportMetrics(scrollTop: 1e12, viewportHeight: 300)   // 2^31 px is ~24 days of rows
        #expect(box.firstVisibleIndex() == 99, "clamped into [0, count)")
    }

    @Test("a runway beyond 2^31 px clamps instead of overflowing")
    func hugeRunwayClamps() {
        let people = (0..<3).map { Person(id: $0, name: "P\($0)") }
        let box = makeDataTableBox(people, id: \.id, maxHeight: "300px",
                                   virtualization: .fixed(rowHeight: 1_000_000_000)) {
            Column("Name", value: \.name)
        }
        // 3 rows × 1e9 px = 3e9 > Int32.max — raw Int math overflows/traps on wasm32.
        #expect(box.runwayHeightPx() == 2_147_483_000, "clamped to the CSS-meaningful cap")
    }
}
