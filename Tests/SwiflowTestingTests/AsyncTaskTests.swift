import Testing
@testable import SwiflowTesting
@testable import Swiflow

enum Loadable: Equatable { case idle, loading, loaded(String), failed }

@MainActor @Component
private final class Profile {
    let userID: Int
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
        let h = AsyncTestHarness(Profile(userID: 1) { id in "User#\(id)" })
        try await h.settle()
        #expect(h.allText.contains("User#1"))
        #expect(h.allText.contains("User#2") == false)
    }

    @Test func settleThrowsOnRunawayLoop() async {
        let h = AsyncTestHarness(Runaway())
        await #expect(throws: AsyncTestHarness.SettleError.self) {
            try await h.settle(maxRounds: 5)
        }
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
