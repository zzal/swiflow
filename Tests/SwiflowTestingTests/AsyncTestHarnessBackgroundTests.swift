import Testing
import Swiflow
import SwiflowQuery
@testable import SwiflowTesting

@MainActor private struct PollQ: Query {
    static var calls = 0
    var queryKey: QueryKey { ["poll"] }
    var refetchInterval: Duration? { .seconds(5) }
    func fetch() async throws -> Int { PollQ.calls += 1; return PollQ.calls }
}
@MainActor private final class Poller: Component {
    var body: VNode {
        let s = query(PollQ())
        return .text(s.data.map(String.init) ?? "…")
    }
}

// .serialized: the three tests share PollQ.calls (a static counter).
@Suite("AsyncTestHarness/background", .serialized)
@MainActor
struct AsyncTestHarnessBackgroundTests {
    @Test("advance(by:) on the manual clock triggers a refetchInterval poll") func advanceDrivesPolling() async throws {
        PollQ.calls = 0
        let h = AsyncTestHarness(Poller(), clock: ManualClock())
        try await h.settle()
        #expect(PollQ.calls == 1)
        try await h.advance(by: .seconds(5))
        #expect(PollQ.calls == 2)
    }

    // Audit VI Wave-3: advance(by:) on the shared-client init was a runtime
    // PRECONDITION CRASH. The harness now recovers the manual clock from the
    // shared client itself (QueryClient exposes its clock), so sharing a
    // manually-clocked client keeps time control; a non-manual clock throws
    // a descriptive error instead of killing the test process.

    @Test("advance(by:) WORKS on a shared client built with a ManualClock") func advanceOnSharedManualClock() async throws {
        PollQ.calls = 0
        let clock = ManualClock()
        let shared = QueryClient(clock: clock)
        let h = AsyncTestHarness(Poller(), queryClient: shared)
        try await h.settle()
        #expect(PollQ.calls == 1)
        try await h.advance(by: .seconds(5))
        #expect(PollQ.calls == 2, "time control threads through the shared client's own clock")
    }

    @Test("advance(by:) on a shared client with a NON-manual clock throws, not crashes") func advanceOnSystemClockThrows() async throws {
        let h = AsyncTestHarness(Poller(), queryClient: QueryClient())
        try await h.settle()
        await #expect(throws: AsyncTestHarness.ClockError.self) {
            try await h.advance(by: .seconds(5))
        }
    }
}
