// Tests/SwiflowTests/Reactivity/StateTests.swift
import Testing
@testable import Swiflow

@Suite("@State")
struct StateTests {

    @Test("Initial value is preserved")
    func initialValue() {
        let state = State(wrappedValue: 42)
        #expect(state.wrappedValue == 42)
    }

    @Test("Mutation updates the underlying storage")
    func mutationUpdates() {
        let state = State(wrappedValue: 0)
        state.wrappedValue = 17
        #expect(state.wrappedValue == 17)
    }

    @Test("projectedValue returns a Binding-shaped pair (read/write)")
    func projectedValueReadWrite() {
        let state = State(wrappedValue: "a")
        let binding = state.projectedValue
        #expect(binding.get() == "a")
        binding.set("b")
        #expect(state.wrappedValue == "b")
    }

    @Test("Without an owner+scheduler, mutation is silent (no crash)")
    func noOwnerSilent() {
        let state = State(wrappedValue: 0)
        state.wrappedValue = 99
        // No scheduler attached — must not crash, must not try to schedule.
        #expect(state.wrappedValue == 99)
    }

    @Test("With owner+scheduler, mutation calls scheduler.markDirty exactly once per assignment")
    func mutationSchedules() {
        final class StubComponent: Component { var body: VNode { .text("") } }
        final class CountingScheduler: Scheduler {
            var markCount = 0
            var lastMarked: AnyComponent?
            func markDirty(_ component: AnyComponent) {
                markCount += 1
                lastMarked = component
            }
            func flush() {}
        }

        let owner = AnyComponent(StubComponent())
        let scheduler = CountingScheduler()
        let state = State(wrappedValue: 0)
        state._setOwner(owner, scheduler: scheduler)

        state.wrappedValue = 1
        state.wrappedValue = 2
        #expect(scheduler.markCount == 2)
        #expect(scheduler.lastMarked?.instance === owner.instance)
    }
}
