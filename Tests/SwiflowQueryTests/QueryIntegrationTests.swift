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

@Component
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

@Component
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

@Component
private final class Child {
    @State var n: Int
    let load: @MainActor @Sendable (Int) -> String
    init(n: Int, load: @escaping @MainActor @Sendable (Int) -> String) { self.n = n; self.load = load }
    var body: VNode {
        let u = query(UserByID(id: n, load: load))
        return p(u.data?.name ?? "…")
    }
}

@Component
private final class Parent {
    let child: Child
    init(child: Child) { self.child = child }
    var body: VNode { div { embed { self.child } } }
}

private enum DemoError: Error { case boom }

/// A main-actor toggle so the test can flip a query from success to failure.
@MainActor private final class FailBox { var failNext = false }

@MainActor private struct ErrQuery: Query {
    let box: FailBox
    var queryKey: QueryKey { ["thing"] }
    func fetch() async throws -> String {
        if box.failNext { throw DemoError.boom }
        return "ok"
    }
}

@Component private final class ErrLoader {
    let box: FailBox
    init(box: FailBox) { self.box = box }
    var body: VNode {
        let u = query(ErrQuery(box: box))
        return div {
            if let d = u.data { p(d) }
            if u.error != nil { p("error") }
        }
    }
}

@Suite("Query/integration")
@MainActor
struct QueryIntegrationTests {
    @Test("Mounting a component fetches and renders its query data") func loadsOnMount() async throws {
        let h = AsyncTestHarness(Profile(userID: 1) { "User#\($0)" }, clock: ManualClock())
        try await h.settle()
        #expect(h.allText.contains("User#1"))
    }

    @Test("Changing the query key refetches and renders the new key's data") func refetchesOnKeyChange() async throws {
        let vm = Profile(userID: 1) { "User#\($0)" }
        let h = AsyncTestHarness(vm, clock: ManualClock())
        try await h.settle()
        #expect(h.allText.contains("User#1"))

        vm.userID = 2
        h.flush()                 // reconcile sees the new key
        try await h.settle()      // fetch for user 2
        #expect(h.allText.contains("User#2"))
    }

    @Test("Two concurrent observations of the same key share a single fetch") func dedupesConcurrentSameKey() async throws {
        let counter = FetchCounter()
        let h = AsyncTestHarness(
            Pair { id in counter.bump(); return "User#\(id)" },
            clock: ManualClock()
        )
        try await h.settle()
        #expect(counter.value == 1)   // one fetch despite two observations
    }

    @Test("invalidate forces a refetch for a mounted observer") func invalidateRefetchesMountedObserver() async throws {
        let counter = FetchCounter()
        let h = AsyncTestHarness(
            Profile(userID: 1) { id in counter.bump(); return "User#\(id)" },
            clock: ManualClock()
        )
        try await h.settle()
        #expect(counter.value == 1)

        h.queryClient.invalidate(["users", 1])
        try await h.settle()
        #expect(counter.value == 2)   // forced refetch
    }

    // Validates the TestRenderer's non-root rerender bracketing: a NESTED
    // component re-rendering on its OWN @State change must reconcile its
    // query (refetch the new key), matching the browser renderer.
    @Test("A nested component re-rendering on its own @State change reconciles its query and refetches") func nestedComponentReconcilesOnOwnStateChange() async throws {
        let child = Child(n: 1) { "User#\($0)" }
        let h = AsyncTestHarness(Parent(child: child), clock: ManualClock())
        try await h.settle()
        #expect(h.allText.contains("User#1"))

        child.n = 2               // the CHILD's own @State → nested rerender path
        h.flush()
        try await h.settle()
        #expect(h.allText.contains("User#2"))
    }

    // Error path (spec §9): a failed revalidation surfaces `error`, retains the
    // prior `data`, and leaves the entry stale so a later trigger retries.
    @Test("A failed revalidation surfaces the error, keeps prior data, and stays stale for retry") func failedRevalidationSurfacesErrorAndKeepsData() async throws {
        let box = FailBox()
        let h = AsyncTestHarness(ErrLoader(box: box), clock: ManualClock())
        try await h.settle()
        #expect(h.allText.contains("ok"))          // first fetch succeeds
        #expect(!h.allText.contains("error"))

        box.failNext = true
        h.queryClient.invalidate(["thing"])        // forced refetch → throws
        try await h.settle()
        #expect(h.allText.contains("ok"))          // prior data retained (SWR)
        #expect(h.allText.contains("error"))       // error surfaced

        box.failNext = false
        h.queryClient.invalidate(["thing"])        // entry still stale → retry succeeds
        try await h.settle()
        #expect(h.allText.contains("ok"))
        #expect(!h.allText.contains("error"))      // error cleared on success
    }
}
