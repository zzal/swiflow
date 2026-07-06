import Testing
@testable import SwiflowQuery

@Suite("Clock")
struct ClockTests {
    @Test("ManualClock starts at its seed instant and advances by exact durations") func manualClockStartsAndAdvances() {
        let clock = ManualClock(.seconds(10))
        #expect(clock.now() == .seconds(10))
        clock.advance(by: .seconds(5))
        #expect(clock.now() == .seconds(15))
        clock.advance(by: .milliseconds(500))
        #expect(clock.now() == .seconds(15) + .milliseconds(500))
    }

    // The browser clock reads `performance.now()`, a Double that grows without
    // bound. On wasm32 `Int` is 32-bit, so the old `.milliseconds(Int(ms))` trapped
    // once uptime passed Int32.max ms ≈ 24.85 days. These pin the widened
    // conversion at the boundary the host's 64-bit Int would otherwise hide.

    @Test("duration() widens past Int32.max so wasm32 uptime beyond ~24.85 days can't trap")
    func durationWidensPastInt32Max() {
        // 2^31 ms is exactly where a 32-bit `Int(ms)` overflows on wasm32.
        #expect(SystemQueryClock.duration(millisecondsSinceOrigin: 2_147_483_648) == .milliseconds(2_147_483_648))
        // A 30-day uptime, comfortably past the trap threshold.
        let thirtyDaysMs = 30.0 * 24 * 60 * 60 * 1000
        #expect(SystemQueryClock.duration(millisecondsSinceOrigin: thirtyDaysMs) == .milliseconds(2_592_000_000))
    }

    @Test("duration() rounds a sub-millisecond reading to the nearest millisecond")
    func durationRoundsToNearestMillisecond() {
        #expect(SystemQueryClock.duration(millisecondsSinceOrigin: 0) == .zero)
        #expect(SystemQueryClock.duration(millisecondsSinceOrigin: 1500.7) == .milliseconds(1501))
        #expect(SystemQueryClock.duration(millisecondsSinceOrigin: 1500.2) == .milliseconds(1500))
    }

    @Test("duration() clamps a non-finite reading to .max instead of trapping")
    func durationClampsNonFinite() {
        // performance.now() is always finite, but a bare Int(.nan)/Int(.infinity)
        // traps even on the host — the `Int64(exactly:) ?? .max` guard turns that
        // into a benign 'maximally stale' reading (forces a refetch, never crashes).
        #expect(SystemQueryClock.duration(millisecondsSinceOrigin: .infinity) == .milliseconds(Int64.max))
        #expect(SystemQueryClock.duration(millisecondsSinceOrigin: .nan) == .milliseconds(Int64.max))
    }
}
