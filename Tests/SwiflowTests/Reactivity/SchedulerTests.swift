// Tests/SwiflowTests/Reactivity/SchedulerTests.swift
import Testing
@testable import Swiflow

@Suite("Scheduler")
struct SchedulerTests {

    final class StubComponent: Component {
        var body: VNode { .text("") }
    }

    @Test("markDirty + flush calls rerender callback once per component")
    func basicFlush() {
        var called: [ObjectIdentifier] = []
        let scheduler = SyncScheduler { any in
            called.append(ObjectIdentifier(any.instance))
        }
        let a = AnyComponent(StubComponent())
        let b = AnyComponent(StubComponent())
        scheduler.markDirty(a)
        scheduler.markDirty(b)
        #expect(called.isEmpty, "flush hasn't been called yet")
        scheduler.flush()
        #expect(called.count == 2)
        #expect(called.contains(ObjectIdentifier(a.instance)))
        #expect(called.contains(ObjectIdentifier(b.instance)))
    }

    @Test("Duplicate markDirty calls deduplicate within a single batch")
    func deduplication() {
        var callCount = 0
        let scheduler = SyncScheduler { _ in callCount += 1 }
        let a = AnyComponent(StubComponent())
        scheduler.markDirty(a)
        scheduler.markDirty(a)
        scheduler.markDirty(a)
        scheduler.flush()
        #expect(callCount == 1, "Three markDirty calls for the same component → one flush invocation")
    }

    @Test("Flush clears the dirty set; subsequent markDirty starts a fresh batch")
    func flushClears() {
        var callCount = 0
        let scheduler = SyncScheduler { _ in callCount += 1 }
        let a = AnyComponent(StubComponent())
        scheduler.markDirty(a)
        scheduler.flush()
        scheduler.flush() // no-op second flush
        #expect(callCount == 1)

        scheduler.markDirty(a)
        scheduler.flush()
        #expect(callCount == 2)
    }

    @Test("Marks scheduled during a flush are deferred to the next batch")
    func reentrantMarkDefers() {
        var callsThisBatch: [ObjectIdentifier] = []
        let a = AnyComponent(StubComponent())
        let b = AnyComponent(StubComponent())
        var scheduler: SyncScheduler!
        scheduler = SyncScheduler { any in
            callsThisBatch.append(ObjectIdentifier(any.instance))
            // Re-mark b while flushing a.
            if any.instance === a.instance && callsThisBatch.count == 1 {
                scheduler.markDirty(b)
            }
        }
        scheduler.markDirty(a)
        scheduler.flush()
        #expect(callsThisBatch.count == 1, "b should NOT have been flushed in this batch")
        scheduler.flush()
        #expect(callsThisBatch.count == 2, "b is flushed on the next batch")
    }

    @Test("Insertion order is preserved across the batch")
    func insertionOrder() {
        var calledOrder: [ObjectIdentifier] = []
        let scheduler = SyncScheduler { any in
            calledOrder.append(ObjectIdentifier(any.instance))
        }
        let a = AnyComponent(StubComponent())
        let b = AnyComponent(StubComponent())
        let c = AnyComponent(StubComponent())
        scheduler.markDirty(b)
        scheduler.markDirty(c)
        scheduler.markDirty(a)
        scheduler.markDirty(b) // re-mark; should not move b's position
        scheduler.flush()
        #expect(calledOrder == [
            ObjectIdentifier(b.instance),
            ObjectIdentifier(c.instance),
            ObjectIdentifier(a.instance),
        ], "Order should follow first-mark insertion, ignoring later re-marks")
    }

    @Test("flush() called from within a callback is a no-op (isFlushing guard)")
    func reentrantFlushIsNoop() {
        // The `isFlushing` guard prevents a callback that itself calls
        // flush() from triggering recursion. Without the guard, a
        // callback that explicitly calls scheduler.flush() inside the
        // rerender hook would re-enter the loop, double-fire the
        // current batch, or stack-overflow on deferred marks.
        var callCount = 0
        var scheduler: SyncScheduler!
        let a = AnyComponent(StubComponent())
        scheduler = SyncScheduler { _ in
            callCount += 1
            scheduler.flush() // must be a no-op; the outer flush is in progress
        }
        scheduler.markDirty(a)
        scheduler.flush()
        #expect(callCount == 1, "Reentrant flush() must not re-invoke callbacks for the current batch")
    }
}
