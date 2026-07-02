// Sources/App/App.swift
import SwiflowDOM
import SwiflowUI
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

@Query(prefix: "users") struct UserByID {
    @Key let id: Int
    var api: FakeAPI = FakeAPI()        // captured dependency; defaulted = test seam
    var tags: Set<QueryTag> { ["users"] }
    func fetch() async throws -> User { await api.user(id) }
}

@Mutation struct RenameUser {
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

@Component
final class QueryRoot {
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
        return VStack(spacing: .lg, align: .start) {
            h1("Query demo")
            HStack(spacing: .sm, align: .center) {
                if let user = u.data { p("Loaded: \(user.name)") }
                else if u.isLoading { p("Loading…") }
                if u.isFetching { Spinner(size: .sm, label: "Fetching") }
            }
            Button("Next user") { self.userID += 1 }

            VStack(spacing: .sm, align: .start) {
                h2("Rename user")
                HStack(spacing: .sm, align: .end) {
                    TextField("New name", text: $newName)
                    Button("Rename", disabled: $rename.isPending) { self.$rename.mutate(self.newName) }
                }
                if $rename.isPending { p("Renaming…") }
                if $rename.isError { p("Error renaming user.") }
            }
        }
        .padding(.xl)
    }
}

@main
struct App {
    @MainActor
    static func main() {
        Swiflow.render(into: "#app") { QueryRoot() }
    }
}
