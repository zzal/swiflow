// Sources/App/App.swift
import SwiflowDOM
import SwiflowQuery

struct User: Equatable, Sendable { let id: Int; let name: String }

/// Simulated API: a non-identity dependency captured by the key.
struct FakeAPI: Sendable {
    func user(_ id: Int) async -> User {
        try? await Task.sleep(nanoseconds: 400_000_000)   // simulate latency
        return User(id: id, name: "User #\(id)")
    }

    func renameUser(_ id: Int, name: String) async throws -> User {
        try? await Task.sleep(nanoseconds: 300_000_000)   // simulate latency
        return User(id: id, name: name)
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

struct RenameUser: Mutation {
    let id: Int
    let api: FakeAPI

    func perform(_ newName: String) async throws -> User {
        try await api.renameUser(id, name: newName)
    }

    func optimistic(_ newName: String) -> [OptimisticEdit] {
        let id = self.id
        return [.update(UserByID(id: id)) { _ in User(id: id, name: newName) }]
    }

    func invalidations(input: String, output: User) -> [Invalidation] {
        [.exact(["users", .int(id)])]
    }
}

@MainActor @Component
final class QueryDemo {
    @State var userID: Int = 1
    @State var newName: String = ""
    @MutationState var rename: RenameUser

    init() {
        self.rename = RenameUser(id: 1, api: FakeAPI())
    }

    var body: VNode {
        let u = query(UserByID(id: userID))
        // Keep rename mutation in sync with the current userID.
        self.rename = RenameUser(id: userID, api: FakeAPI())
        return div {
            h1("Query demo")
            div {
                if let user = u.data { p("Loaded: \(user.name)") }
                else if u.isLoading { p("Loading…") }
                if u.isFetching { span { text(" ⟳") } }
            }
            button("Next user", .on(.click) { self.userID += 1 })
            div {
                h2("Rename user")
                input(.value($newName), .on(.input) { self.newName = $0.targetValue ?? "" })
                button("Rename", .on(.click) { self.$rename.mutate(self.newName) },
                       .attr("disabled", $rename.isPending))
                if $rename.isPending { p("Renaming…") }
                if $rename.isError { p("Error renaming user.") }
            }
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
