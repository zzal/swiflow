// Tests/SwiflowQueryTests/MutationEngineTests.swift
import Testing
import Swiflow
@testable import SwiflowQuery

@MainActor private final class Dummy: Component { var body: VNode { .text("") } }
private enum Boom: Error { case nope }

@MainActor
private struct Save: Mutation {
    let run: @MainActor @Sendable (String) async throws -> Int
    func perform(_ input: String) async throws -> Int { try await run(input) }
}

@Suite("Mutation/engine")
@MainActor
struct MutationEngineTests {
    private func wiredHandle(_ m: Save, _ client: QueryClient)
        -> (MutationHandle<Save>, MutationRuntime<Save>) {
        let rt = MutationRuntime<Save>()
        rt.wire(owner: AnyComponent(Dummy()), scheduler: SyncScheduler { _ in }, client: client)
        return (MutationHandle(runtime: rt, mutation: m), rt)
    }
    private func settle(_ c: QueryClient) async { for t in c.inFlightTasks() { await t.value } }

    @Test func successSetsData() async {
        let client = QueryClient(clock: ManualClock())
        let (h, rt) = wiredHandle(Save { $0.count }, client)
        h.mutate("abcd")
        await settle(client)
        #expect(rt.status == .success)
        #expect(rt.data == 4)
        #expect(rt.error == nil)
    }

    @Test func failureSetsError() async {
        let client = QueryClient(clock: ManualClock())
        let (h, rt) = wiredHandle(Save { _ in throw Boom.nope }, client)
        h.mutate("x")
        await settle(client)
        #expect(rt.status == .error)
        #expect(rt.error != nil)
        #expect(rt.data == nil)
    }

    @Test func mutateAsyncReturnsAndRethrows() async throws {
        let client = QueryClient(clock: ManualClock())
        let (ok, _) = wiredHandle(Save { $0.count }, client)
        let out = try await ok.mutateAsync("hello")
        #expect(out == 5)

        let (bad, rt) = wiredHandle(Save { _ in throw Boom.nope }, client)
        await #expect(throws: Boom.self) { try await bad.mutateAsync("x") }
        #expect(rt.status == .error)        // same error also stored on the handle
    }

    @Test func resetReturnsToIdle() async {
        let client = QueryClient(clock: ManualClock())
        let (h, rt) = wiredHandle(Save { $0.count }, client)
        h.mutate("ab"); await settle(client)
        #expect(rt.status == .success)
        h.reset()
        #expect(rt.status == .idle)
        #expect(rt.data == nil)
    }
}
