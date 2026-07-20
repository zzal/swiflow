// Tests/SwiflowTimingTests/ManualTimersTests.swift
//
// Direct coverage for the host `ManualTimers` queue behind `after(_:do:)`.
// Previously exercised only indirectly through ToastTests; these pin the
// schedule/advance/cancel/reset funnels themselves. Host-only by nature —
// on wasm32 `after()` is the JSOneshotClosure implementation, which has no
// host-drivable queue.
//
// ManualTimers is a process-global seam, so this is the ONE suite that owns
// it: `.serialized`, `reset()` before each test. `after()` returns a handle
// whose isolated `deinit` cancels the timer, so every live timer must be
// held for as long as it should stay armed — the tests keep handles in a
// local array (`keep`) exactly as a real owner keeps `dismissTimer`.
import Testing
@testable import SwiflowTiming

@Suite("ManualTimers", .serialized)
@MainActor
struct ManualTimersTests {

    @Test("a scheduled timer fires once when advanced past its duration")
    func firesOncePastDuration() {
        ManualTimers.reset()
        var fired = 0
        let keep = after(4) { fired += 1 }
        #expect(ManualTimers.pendingCount == 1)
        ManualTimers.advance(by: 3.9)
        #expect(fired == 0)
        ManualTimers.advance(by: 0.1)
        #expect(fired == 1)
        #expect(ManualTimers.pendingCount == 0)
        ManualTimers.advance(by: 100)   // already fired → no re-fire
        #expect(fired == 1)
        withExtendedLifetime(keep) {}
    }

    @Test("repeated fractional advances don't lose time to Double residue")
    func fractionalResidue() {
        ManualTimers.reset()
        var fired = false
        let keep = after(4) { fired = true }
        // 4 − 3.9 − 0.1 leaves ~8e-17; the 1e-9 tolerance must still fire it.
        ManualTimers.advance(by: 3.9)
        ManualTimers.advance(by: 0.1)
        #expect(fired)
        withExtendedLifetime(keep) {}
    }

    @Test("cancel() before the due time drops the timer without firing")
    func cancelBeforeDue() {
        ManualTimers.reset()
        var fired = false
        let h = after(4) { fired = true }
        h.cancel()
        #expect(ManualTimers.pendingCount == 0)
        ManualTimers.advance(by: 10)
        #expect(!fired)
    }

    @Test("dropping the handle without cancel() still cancels (isolated deinit)")
    func deinitCancels() {
        ManualTimers.reset()
        var fired = false
        do { _ = after(4) { fired = true } }   // handle deallocated here
        #expect(ManualTimers.pendingCount == 0)
        ManualTimers.advance(by: 10)
        #expect(!fired)
    }

    @Test("due timers fire in ascending-remaining order")
    func dueOrder() {
        ManualTimers.reset()
        var order: [Int] = []
        let keep = [after(3) { order.append(3) },
                    after(1) { order.append(1) },
                    after(2) { order.append(2) }]
        ManualTimers.advance(by: 5)
        #expect(order == [1, 2, 3])
        withExtendedLifetime(keep) {}
    }

    @Test("a timer scheduled from within a firing body joins the queue, not the same advance")
    func rescheduleWithinBody() {
        ManualTimers.reset()
        var inner = false
        var nested: TimerHandle?
        let keep = after(1) { nested = after(1) { inner = true } }
        ManualTimers.advance(by: 5)   // fires the outer; inner joins fresh
        #expect(!inner)
        #expect(ManualTimers.pendingCount == 1)
        ManualTimers.advance(by: 1)
        #expect(inner)
        withExtendedLifetime((keep, nested)) {}
    }

    @Test("reset() drops every pending timer without firing")
    func resetDropsAll() {
        ManualTimers.reset()
        var fired = 0
        let keep = [after(1) { fired += 1 }, after(2) { fired += 1 }]
        #expect(ManualTimers.pendingCount == 2)
        ManualTimers.reset()
        #expect(ManualTimers.pendingCount == 0)
        ManualTimers.advance(by: 100)
        #expect(fired == 0)
        withExtendedLifetime(keep) {}
    }
}
