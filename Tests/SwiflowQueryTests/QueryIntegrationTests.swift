import Testing
import Swiflow
import SwiflowTesting
@testable import SwiflowQuery

@MainActor
private struct User: Equatable, Sendable { let id: Int; let name: String }

@MainActor
private struct UserByID: Query {
    let id: Int
    let load: @MainActor @Sendable (Int) -> String
    var queryKey: QueryKey { ["users", .int(id)] }
    func fetch() async throws -> User { User(id: id, name: load(id)) }
}

@MainActor @Component
private final class Profile {
    @State var userID: Int
    let load: @MainActor @Sendable (Int) -> String
    init(userID: Int, load: @escaping @MainActor @Sendable (Int) -> String) {
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

@MainActor
private final class FetchCounter {
    private(set) var value = 0
    func bump() { value += 1 }
}

@MainActor @Component
private final class Pair {
    let load: @MainActor @Sendable (Int) -> String
    init(load: @escaping @MainActor @Sendable (Int) -> String) { self.load = load }
    var body: VNode {
        let a = query(UserByID(id: 7, load: load))
        let b = query(UserByID(id: 7, load: load))   // same key, observed twice
        return div {
            p(a.data?.name ?? "…")
            p(b.data?.name ?? "…")
        }
    }
}

@MainActor @Component
private final class Child {
    @State var n: Int
    let load: @MainActor @Sendable (Int) -> String
    init(n: Int, load: @escaping @MainActor @Sendable (Int) -> String) { self.n = n; self.load = load }
    var body: VNode {
        let u = query(UserByID(id: n, load: load))
        return p(u.data?.name ?? "…")
    }
}

@MainActor @Component
private final class Parent {
    let child: Child
    init(child: Child) { self.child = child }
    var body: VNode { div { embed { self.child } } }
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

    @Test func refetchesOnKeyChange() async throws {
        let client = QueryClient(clock: ManualClock())
        let vm = Profile(userID: 1) { "User#\($0)" }
        let h = AsyncTestHarness(vm, queryClient: client)
        try await h.settle()
        #expect(h.allText.contains("User#1"))

        vm.userID = 2
        h.flush()                 // reconcile sees the new key
        try await h.settle()      // fetch for user 2
        #expect(h.allText.contains("User#2"))
    }

    @Test func dedupesConcurrentSameKey() async throws {
        let client = QueryClient(clock: ManualClock())
        let counter = FetchCounter()
        let h = AsyncTestHarness(
            Pair { id in counter.bump(); return "User#\(id)" },
            queryClient: client
        )
        try await h.settle()
        #expect(counter.value == 1)   // one fetch despite two observations
    }

    @Test func invalidateRefetchesMountedObserver() async throws {
        let client = QueryClient(clock: ManualClock())
        let counter = FetchCounter()
        let h = AsyncTestHarness(
            Profile(userID: 1) { id in counter.bump(); return "User#\(id)" },
            queryClient: client
        )
        try await h.settle()
        #expect(counter.value == 1)

        client.invalidate(["users", 1])
        try await h.settle()
        #expect(counter.value == 2)   // forced refetch
    }

    // Validates the TestRenderer's non-root rerender bracketing: a NESTED
    // component re-rendering on its OWN @State change must reconcile its
    // query (refetch the new key), matching the browser renderer.
    @Test func nestedComponentReconcilesOnOwnStateChange() async throws {
        let client = QueryClient(clock: ManualClock())
        let child = Child(n: 1) { "User#\($0)" }
        let h = AsyncTestHarness(Parent(child: child), queryClient: client)
        try await h.settle()
        #expect(h.allText.contains("User#1"))

        child.n = 2               // the CHILD's own @State → nested rerender path
        h.flush()
        try await h.settle()
        #expect(h.allText.contains("User#2"))
    }
}
