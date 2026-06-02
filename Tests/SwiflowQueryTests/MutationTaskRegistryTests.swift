// Tests/SwiflowQueryTests/MutationTaskRegistryTests.swift
import Testing
@testable import SwiflowQuery

@Suite("QueryClient/mutationTasks")
@MainActor
struct MutationTaskRegistryTests {
    @Test func registeredTaskAppearsInFlightThenSelfRemoves() async {
        let client = QueryClient(clock: ManualClock())
        let token = client.nextMutationTaskToken()
        let started = client.inFlightTasks().count
        let task = Task<Void, Never> {
            try? await Task.sleep(for: .milliseconds(1))
            client.removeMutationTask(token)
        }
        client.storeMutationTask(token, task)
        #expect(client.inFlightTasks().count == started + 1)
        await task.value
        #expect(client.inFlightTasks().count == started)   // self-removed by token
    }

    @Test func tokensAreUnique() {
        let client = QueryClient(clock: ManualClock())
        #expect(client.nextMutationTaskToken() != client.nextMutationTaskToken())
    }
}
