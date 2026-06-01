import Testing
@testable import Swiflow

@MainActor
@Suite(.serialized)   // global registry state — run serially, reset between tests
struct TaskRuntimeTests {

    init() { SwiflowTaskRuntime._resetForTesting() }

    @Test func noTokenMeansWriteIsKept() {
        #expect(SwiflowTaskRuntime.shouldDropWrite() == false)
    }

    @Test func tokenPropagatesAcrossAwait() async {
        let slot = TaskSlot(id: SwiflowTaskRuntime.allocateSlotID())
        var sawTokenAfterAwait = false
        SwiflowTaskRuntime.start(slot) {
            await Task.yield()
            sawTokenAfterAwait = (SwiflowTaskLocal.current?.slotID == slot.id)
        }
        for t in SwiflowTaskRuntime.inFlightTasks() { await t.value }
        #expect(sawTokenAfterAwait == true)
    }

    @Test func supersededTaskWriteIsDropped() async {
        let slot = TaskSlot(id: SwiflowTaskRuntime.allocateSlotID())
        var staleSawDrop = false
        var freshSawKeep = false
        // First run captures generation 1.
        SwiflowTaskRuntime.start(slot) {
            await Task.yield()                       // suspend so the restart below wins
            staleSawDrop = SwiflowTaskRuntime.shouldDropWrite()   // expect true: superseded
        }
        // Restart (generation 2) — simulates a rerunOn change.
        SwiflowTaskRuntime.start(slot) {
            freshSawKeep = (SwiflowTaskRuntime.shouldDropWrite() == false) // expect kept
        }
        for t in SwiflowTaskRuntime.inFlightTasks() { await t.value }
        #expect(staleSawDrop == true)
        #expect(freshSawKeep == true)
    }

    @Test func cancelledSlotDropsLateWrite() async {
        let slot = TaskSlot(id: SwiflowTaskRuntime.allocateSlotID())
        var sawDrop = false
        SwiflowTaskRuntime.start(slot) {
            await Task.yield()
            sawDrop = SwiflowTaskRuntime.shouldDropWrite()   // slot torn down -> true
        }
        SwiflowTaskRuntime.cancel(slot)                      // dead slot
        for t in SwiflowTaskRuntime.inFlightTasks() { await t.value }
        #expect(sawDrop == true)
    }

    @Test func stateWriteIsRevertedUnderStaleToken() async {
        let probe = GuardProbe()
        // Allocate a slot and bump it twice so generation 1 is stale.
        let slot = TaskSlot(id: SwiflowTaskRuntime.allocateSlotID())
        slot.generation = 1
        SwiflowTaskRuntime.liveGenerations[slot.id] = 2   // live gen is 2; token gen 1 is stale
        let staleToken = SwiflowTaskToken(slotID: slot.id, generation: 1)

        await SwiflowTaskLocal.$current.withValue(staleToken) {
            probe.value = 99            // generated didSet should revert this
        }
        #expect(probe.value == 0)       // reverted to oldValue

        // A write with no token proceeds normally.
        probe.value = 42
        #expect(probe.value == 42)
    }
}

@MainActor @Component
private final class GuardProbe {
    @State var value: Int = 0
    var body: VNode { div { p("\(value)") } }
}
