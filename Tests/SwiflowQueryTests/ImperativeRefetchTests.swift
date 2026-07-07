// Tests/SwiflowQueryTests/ImperativeRefetchTests.swift
//
// Imperative refetch/invalidate (audit II Wave-2 #5): a "Refresh" button
// finally has a supported path. `QueryState.refetch()` rides a weak client +
// key captured at observation time (root-correct by construction, works in
// handlers where the render ambient is gone); `Component.invalidate` resolves
// the active render's client or falls back to the most recently rendered
// root's (`RenderObserverBox.lastRendered`).
import Testing
import Swiflow
import SwiflowTesting
@testable import SwiflowQuery

// MARK: - Direct QueryState.refetch() semantics (BG harness)

@Suite("QueryState/refetch")
@MainActor
struct QueryStateRefetchTests {
    @Test("refetch() forces stale and refetches; the fresh value lands")
    func refetchRefetches() async {
        let bg = BG(retry: .none)          // staleTime 9999s — never auto-refetches
        await bg.settle()
        #expect(bg.probe.calls == 1)

        let snapshot = makeSnapshot(from: bg.entry, as: [String].self,
                                    client: bg.client, key: ["k"])
        snapshot.refetch()
        await bg.settle()
        #expect(bg.probe.calls == 2, "refetch must bypass staleTime and refetch now")
        #expect(bg.entry.value as? [String] == ["v2"])   // probe returns v<calls>
    }

    @Test("refetch() supersedes: the entry's generation is bumped")
    func refetchSupersedes() async {
        let bg = BG(retry: .none)
        await bg.settle()
        let genBefore = bg.entry.generation
        let snapshot = makeSnapshot(from: bg.entry, as: [String].self,
                                    client: bg.client, key: ["k"])
        snapshot.refetch()
        #expect(bg.entry.generation == genBefore + 1)
        await bg.settle()
    }

    @Test("refetch() is a no-op after the owning client is gone (weak capture)")
    func refetchNoOpAfterClientTeardown() async {
        var snapshot: QueryState<[String]>
        do {
            let bg = BG(retry: .none)
            await bg.settle()
            snapshot = makeSnapshot(from: bg.entry, as: [String].self,
                                    client: bg.client, key: ["k"])
        }
        // The BG world (and its client) is out of scope; the weak capture
        // self-clears. Must not crash, must not retain.
        snapshot.refetch()
        #expect(snapshot.client == nil)
    }

    @Test("refetch() on a snapshot with no observation behind it is a no-op")
    func refetchNoOpWithoutObservation() {
        // The `query(_:)` outside-a-render fallback constructs a bare state.
        let bare = QueryState<Int>(isLoading: true, isFetching: true)
        bare.refetch()   // nothing to do — and nothing to crash on
        #expect(bare.key == nil)
    }
}

// MARK: - Full-stack: handler-time refetch + Component.invalidate

@MainActor private final class LoadCounter {
    private(set) var calls = 0
    func next() -> String { calls += 1; return "load#\(calls)" }
}

@MainActor private struct CountedQuery: Query {
    let counter: LoadCounter
    var queryKey: QueryKey { ["counted"] }
    var staleTime: Duration { .seconds(9999) }   // only imperative paths refetch
    func fetch() async throws -> String { counter.next() }
}

/// A component with a query and two imperative buttons — the audit's missing
/// "Refresh" capability, driven at HANDLER time (between renders, where
/// `RenderObserverBox.current` is nil).
@Component private final class Refresher {
    let counter: LoadCounter
    init(counter: LoadCounter) { self.counter = counter }
    var body: VNode {
        let state = query(CountedQuery(counter: counter))
        return div {
            p(state.data ?? "…")
            button("Refresh").on(.click) { _ in state.refetch() }
            button("Invalidate").on(.click) { _ in
                self.invalidate(CountedQuery(counter: self.counter))
            }
            button("InvalidateTag").on(.click) { _ in self.invalidate(tag: "nope") }
        }
    }
}

@Suite("Component/imperative invalidate")
@MainActor
struct ImperativeInvalidateTests {
    @Test("a handler-time QueryState.refetch() refetches — the Refresh button works")
    func refreshButtonWorks() async throws {
        let counter = LoadCounter()
        let h = AsyncTestHarness(Refresher(counter: counter), clock: ManualClock())
        try await h.settle()
        #expect(h.allText.contains("load#1"))

        h.click("button", text: "Refresh")   // handler runs OUTSIDE any render
        try await h.settle()
        #expect(h.allText.contains("load#2"), "refetch from a click handler must reach the root's client")
    }

    @Test("a handler-time Component.invalidate(query) refetches via the last-rendered fallback")
    func typedInvalidateWorksInHandlers() async throws {
        let counter = LoadCounter()
        let h = AsyncTestHarness(Refresher(counter: counter), clock: ManualClock())
        try await h.settle()
        #expect(h.allText.contains("load#1"))

        // Between renders the render ambient is uninstalled; the imperative
        // client resolves through RenderObserverBox.lastRendered.
        #expect(RenderObserverBox.current == nil)
        h.click("button", text: "Invalidate")
        try await h.settle()
        #expect(h.allText.contains("load#2"))
    }

    @Test("invalidating a tag no query carries refetches nothing")
    func unmatchedTagIsANoOp() async throws {
        let counter = LoadCounter()
        let h = AsyncTestHarness(Refresher(counter: counter), clock: ManualClock())
        try await h.settle()
        #expect(counter.calls == 1)

        h.click("button", text: "InvalidateTag")
        try await h.settle()
        #expect(counter.calls == 1, "an unmatched tag must not refetch anything")
    }
}
