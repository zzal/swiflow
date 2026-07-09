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
    // Only the stable dependency lives on the mutation. The VARYING data
    // (which user, and the new name) travels in `Input` at call time — so the
    // @MutationState instance is built once and never rebuilt per render. Baking
    // a changing `let id` into the mutation is the resync trap this demo used to
    // model: it forced a `self.rename = RenameUser(id: userID, …)` inside `body`
    // on every render just to keep the captured id current.
    var api: FakeAPI = FakeAPI()

    struct Input: Sendable {
        let id: Int
        let name: String
    }

    func perform(_ input: Input) async throws -> User {
        try await api.renameUser(input.id, name: input.name)
    }

    // No invalidations override: the default derives the refetch from the
    // UserByID key that optimistic() declares — one source of truth for
    // "what this mutation touches."
    func optimistic(_ input: Input) -> [OptimisticEdit] {
        [.update(UserByID(id: input.id)) { _ in User(id: input.id, name: input.name) }]
    }
}

@Component
final class QueryRoot {
    @State var userID: Int = 1
    @State var newName: String = ""
    // Stable across renders — @Component synthesizes `self.rename = RenameUser()`
    // (api is defaulted), and it is never reassigned. The current userID reaches
    // the mutation through `Input` at the call site, not through the instance.
    @MutationState var rename: RenameUser

    var body: VNode {
        let u = query(UserByID(id: userID))
        return VStack(spacing: .lg, align: .start) {
            h1("Query demo")
            HStack(spacing: .sm, align: .center) {
                if let user = u.data { p("Loaded: \(user.name)") }
                else if u.isLoading { p("Loading…") }
                if u.isFetching { Spinner(size: .sm, label: "Fetching") }
            }
            HStack(spacing: .sm, align: .center) {
                Button("Next user") { self.userID += 1 }
                // Imperative refetch: the snapshot carries its client + key,
                // so a click handler can force this exact query stale and
                // refetch it — watch the Spinner flash (FakeAPI's 400ms).
                Button("Refresh") { u.refetch() }
            }

            VStack(spacing: .sm, align: .start) {
                h2("Rename user")
                HStack(spacing: .sm, align: .end) {
                    TextField("New name", text: $newName)
                    Button("Rename", disabled: $rename.isPending) {
                        // Varying data flows in via Input — no per-render resync.
                        self.$rename.mutate(.init(id: self.userID, name: self.newName))
                    }
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
