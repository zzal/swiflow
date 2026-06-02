// Tests/SwiflowQueryTests/InFlightRegistryTests.swift
import Testing
@testable import SwiflowQuery

@Suite("InFlightRegistry")
@MainActor
struct InFlightRegistryTests {
    @Test func trackedTaskAppearsThenSelfRemoves() async {
        let reg = InFlightRegistry()
        reg.track { try? await Task.sleep(for: .milliseconds(1)) }
        let handles = reg.current()
        #expect(handles.count == 1)
        for t in handles { await t.value }
        #expect(reg.current().isEmpty)   // self-removed on completion
    }

    @Test func concurrentTrackedTasksGetDistinctSlots() async {
        let reg = InFlightRegistry()
        reg.track { try? await Task.sleep(for: .milliseconds(1)) }
        reg.track { try? await Task.sleep(for: .milliseconds(1)) }
        #expect(reg.current().count == 2)   // distinct tokens — neither overwrote the other
        for t in reg.current() { await t.value }
        #expect(reg.current().isEmpty)
    }

    @Test func clientFoldsMutationTasksIntoInFlight() async {
        let client = QueryClient(clock: ManualClock())
        let started = client.inFlightTasks().count
        client.inFlightMutations.track { try? await Task.sleep(for: .milliseconds(1)) }
        #expect(client.inFlightTasks().count == started + 1)
        for t in client.inFlightTasks() { await t.value }
        #expect(client.inFlightTasks().count == started)
    }
}
