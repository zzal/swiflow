// Sources/App/App.swift
import SwiflowWeb
import SwiflowQuery

struct User: Equatable, Sendable { let id: Int; let name: String }

/// Simulated API: a non-identity dependency captured by the key.
struct FakeAPI: Sendable {
    func user(_ id: Int) async -> User {
        try? await Task.sleep(nanoseconds: 400_000_000)   // simulate latency
        return User(id: id, name: "User #\(id)")
    }
}

struct UserByID: Query {
    let id: Int
    let api: FakeAPI
    var queryKey: QueryKey { ["users", .int(id)] }
    var tags: Set<QueryTag> { ["users"] }
    func fetch() async throws -> User { await api.user(id) }

    init(id: Int, api: FakeAPI = FakeAPI()) { self.id = id; self.api = api }
}

@MainActor @Component
final class QueryDemo {
    @State var userID: Int = 1

    var body: VNode {
        let u = query(UserByID(id: userID))
        return div {
            h1("Query demo")
            div {
                if let user = u.data { p("Loaded: \(user.name)") }
                else if u.isLoading { p("Loading…") }
                if u.isFetching { span { text(" ⟳") } }
            }
            button("Next user", .on(.click) { self.userID += 1 })
        }
    }
}

@main
struct App {
    @MainActor
    static func main() {
        Swiflow.render(into: "#app") { QueryDemo() }
    }
}
