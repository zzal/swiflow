import Testing
import Swiflow
import SwiflowTesting
@testable import SwiflowQuery

@MainActor
private struct User: Equatable, Sendable { let id: Int; let name: String }

@MainActor
private struct UserByID: Query {
    let id: Int
    let load: @Sendable (Int) -> String
    var queryKey: QueryKey { ["users", .int(id)] }
    func fetch() async throws -> User { User(id: id, name: load(id)) }
}

@MainActor @Component
private final class Profile {
    @State var userID: Int
    let load: @Sendable (Int) -> String
    init(userID: Int, load: @escaping @Sendable (Int) -> String) {
        self.userID = userID; self.load = load
    }
    var body: VNode {
        let u = query(UserByID(id: userID, load: load))
        return div {
            if let user = u.data { p(user.name) }
            else if u.isLoading { p("Loading…") }
        }
    }
}

@Suite("Query/integration")
@MainActor
struct QueryIntegrationTests {
    @Test func loadsOnMount() async throws {
        let client = QueryClient(clock: ManualClock())
        let h = AsyncTestHarness(Profile(userID: 1) { "User#\($0)" }, queryClient: client)
        try await h.settle()
        #expect(h.allText.contains("User#1"))
    }
}
