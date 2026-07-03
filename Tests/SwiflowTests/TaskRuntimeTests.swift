import Testing
@testable import Swiflow

@MainActor
@Suite("Task runtime")
struct TaskRuntimeTests {

    // Each test gets its own TaskScope (swift-testing makes a fresh suite
    // instance per test). In-flight tasks register here, isolated from other
    // tests sharing the process — no global reset or .serialized needed:
    // slot IDs are globally unique so `liveGenerations` keys never collide
    // across tests.
    let scope = TaskScope()

    /// Spawn a task in this test's scope — mirrors how a renderer installs its
    /// scope around the synchronous diff pass that calls `start`.
    private func start(_ slot: TaskSlot, _ body: @escaping TaskBody) {
        SwiflowTaskRuntime.withScope(scope) { SwiflowTaskRuntime.start(slot, body: body) }
    }

    /// Await this scope's in-flight tasks to completion.
    private func drain() async {
        for t in scope.inFlightTasks() { await t.value }
    }

    @Test("Writes outside any task token are always kept") func noTokenMeansWriteIsKept() {
        #expect(SwiflowTaskRuntime.shouldDropWrite() == false)
    }

    @Test("The task-local token survives a suspension point") func tokenPropagatesAcrossAwait() async {
        let slot = TaskSlot(id: SwiflowTaskRuntime.allocateSlotID())
        var sawTokenAfterAwait = false
        start(slot) {
            await Task.yield()
            sawTokenAfterAwait = (SwiflowTaskLocal.current?.slotID == slot.id)
        }
        await drain()
        #expect(sawTokenAfterAwait == true)
    }

    @Test("Restarting a slot drops the stale run's writes but keeps the fresh run's") func supersededTaskWriteIsDropped() async {
        let slot = TaskSlot(id: SwiflowTaskRuntime.allocateSlotID())
        var staleSawDrop = false
        var freshSawKeep = false
        // First run captures generation 1.
        start(slot) {
            await Task.yield()                       // suspend so the restart below wins
            staleSawDrop = SwiflowTaskRuntime.shouldDropWrite()   // expect true: superseded
        }
        // Restart (generation 2) — simulates a rerunOn change.
        start(slot) {
            freshSawKeep = (SwiflowTaskRuntime.shouldDropWrite() == false) // expect kept
        }
        await drain()
        #expect(staleSawDrop == true)
        #expect(freshSawKeep == true)
    }

    @Test("A write arriving after its slot is cancelled is dropped") func cancelledSlotDropsLateWrite() async {
        let slot = TaskSlot(id: SwiflowTaskRuntime.allocateSlotID())
        var sawDrop = false
        start(slot) {
            await Task.yield()
            sawDrop = SwiflowTaskRuntime.shouldDropWrite()   // slot torn down -> true
        }
        SwiflowTaskRuntime.cancel(slot)                      // dead slot
        await drain()
        #expect(sawDrop == true)
    }

    @Test("@State didSet reverts a write made under a stale task token") func stateWriteIsRevertedUnderStaleToken() async {
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

@Component
private final class GuardProbe {
    @State var value: Int = 0
    var body: VNode { div { p("\(value)") } }
}
