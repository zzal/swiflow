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
}
