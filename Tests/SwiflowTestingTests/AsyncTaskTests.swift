import Testing
@testable import SwiflowTesting
@testable import Swiflow

private enum Loadable: Equatable { case idle, loading, loaded(String), failed }

@MainActor @Component
private final class Profile {
    @State var userID: Int
    let fetch: @Sendable (Int) async -> String
    @State var state: Loadable = .idle

    init(userID: Int, fetch: @escaping @Sendable (Int) async -> String) {
        self.userID = userID
        self.fetch = fetch
    }

    var body: VNode {
        div {
            switch state {
            case .loaded(let name): p(name)
            case .loading:          p("…")
            default:                p("idle")
            }
        }
        .task(rerunOn: userID) {
            self.state = .loading
            let name = await self.fetch(self.userID)
            self.state = .loaded(name)
        }
    }
}

@MainActor
@Suite(.serialized)
struct AsyncTaskTests {

    init() { SwiflowTaskRuntime._resetForTesting() }

    @Test func settleDrivesTaskToSuccess() async throws {
        let h = AsyncTestHarness(Profile(userID: 1) { id in "User#\(id)" })
        try await h.settle()
        #expect(h.allText.contains("User#1"))
    }

    @Test func supersededRunDoesNotClobberNewerState() async throws {
        // The mount spawns task A (userID 1) but it has not run yet (no MainActor
        // suspension since `start`). Changing the dependency and flushing makes
        // reconcile cancel A and start B (userID 2) — both still pending. `settle`
        // then runs both: A is superseded, so EVERY write it makes (including its
        // final `.loaded("User#1")`) is dropped by the generation guard; B is live
        // and wins. The stale value must never reach the rendered DOM.
        let vm = Profile(userID: 1) { id in "User#\(id)" }
        let h = AsyncTestHarness(vm)
        vm.userID = 2
        h.flush()
        try await h.settle()
        #expect(h.allText.contains("User#2"))
        #expect(h.allText.contains("User#1") == false)
    }

    @Test func settleThrowsOnRunawayLoop() async {
        let h = AsyncTestHarness(Runaway())
        await #expect(throws: AsyncTestHarness.SettleError.self) {
            try await h.settle(maxRounds: 5)
        }
    }

    @Test func changingDependencyRefetchesAfterSettle() async throws {
        let vm = Profile(userID: 1) { id in "User#\(id)" }
        let h = AsyncTestHarness(vm)
        try await h.settle()                 // task A fully completes
        #expect(h.allText.contains("User#1"))

        vm.userID = 2                         // change dep on an already-settled component
        h.flush()                             // reconcile: rerun -> task B
        try await h.settle()                  // task B completes
        #expect(h.allText.contains("User#2"))
        #expect(h.allText.contains("User#1") == false)
    }
}

@MainActor @Component
private final class Runaway {
    @State var n: Int = 0
    var body: VNode {
        div { p("\(n)") }
            .task(rerunOn: n) { self.n += 1 }   // every run changes the dep -> reruns forever
    }
}
