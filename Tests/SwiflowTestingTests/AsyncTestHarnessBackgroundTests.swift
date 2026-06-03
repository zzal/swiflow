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

@Suite("AsyncTestHarness/background")
@MainActor
struct AsyncTestHarnessBackgroundTests {
    @Test func advanceDrivesPolling() async throws {
        PollQ.calls = 0
        let h = AsyncTestHarness(Poller(), clock: ManualClock())
        try await h.settle()
        #expect(PollQ.calls == 1)
        try await h.advance(by: .seconds(5))
        #expect(PollQ.calls == 2)
    }
}
