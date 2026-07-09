// Tests/SwiflowQueryTests/QueryDiagnosticsTests.swift
//
// Audit II Wave-3 diagnostics: the three silent-degradation paths get a
// voice. (1) query() outside a render / against a non-QueryClient observer
// returned a forever-loading snapshot with zero signal — now a once-per-
// process swiflowWarn distinguishing the two situations. (2) A query-key
// collision across Value types read as data == nil forever via
// `entry.value as? V` — now a DEBUG swiflowDiagnostic at the failed cast.
// (3) A prefix invalidate fanning out to >20 live entries is a refetch
// storm that reads like one line of code — now noted.
import Testing
import Swiflow
@testable import SwiflowQuery

@MainActor
private final class Dummy: Component { var body: VNode { .text("") } }

/// A RenderObserver that is not a QueryClient — the "wrong observer" case.
@MainActor
private final class NotAQueryClient: RenderObserver {
    package func willEvaluate(owner: AnyComponent, scheduler: (any Scheduler)?) {}
    package func didEvaluate() {}
    package func componentDidUnmount(_ owner: AnyComponent) {}
}

private struct IntQuery: Query {
    var queryKey: QueryKey { ["collide"] }
    func fetch() async throws -> Int { 1 }
}

@MainActor
private final class OwnerBag {
    var owners: [AnyComponent] = []
    func keep(_ owner: AnyComponent) { owners.append(owner) }
}

@Suite("Query diagnostics", .serialized)
@MainActor
struct QueryDiagnosticsTests {

    /// Capture swiflowWarn messages around `body`, resetting the once-per-
    /// process dedupe first so every test observes its own warns.
    private func capturingWarns(_ body: () -> Void) -> [String] {
        QueryAmbientDiagnostics._resetForTests()
        var captured: [String] = []
        let prior = _swiflowWarnOverride
        _swiflowWarnOverride = { captured.append($0) }
        defer { _swiflowWarnOverride = prior }
        body()
        return captured
    }

    private func capturingDiagnostics(_ body: () -> Void) -> [String] {
        var captured: [String] = []
        let prior = _swiflowDiagnosticOverride
        _swiflowDiagnosticOverride = { captured.append($0) }
        defer { _swiflowDiagnosticOverride = prior }
        body()
        return captured
    }

    // MARK: - query() ambient failures

    @Test("query() outside a render warns once and returns the loading placeholder")
    func outsideRenderWarnsOnce() {
        let component = Dummy()
        let warns = capturingWarns {
            let s1 = component.query(IntQuery())
            let s2 = component.query(IntQuery())   // second call: deduped
            #expect(s1.isLoading && s1.data == nil)
            #expect(s2.isLoading)
        }
        #expect(warns.count == 1)
        #expect(warns[0].contains("outside a render pass"))
        #expect(warns[0].contains("permanently-loading"))
    }

    @Test("query() against a non-QueryClient observer warns once, naming the type")
    func wrongObserverWarnsOnce() {
        let component = Dummy()
        let observer = NotAQueryClient()
        RenderObserverBox.current = observer
        defer { RenderObserverBox.current = nil }
        let warns = capturingWarns {
            _ = component.query(IntQuery())
            _ = component.query(IntQuery())
        }
        #expect(warns.count == 1)
        #expect(warns[0].contains("NotAQueryClient"))
        #expect(warns[0].contains("instead of a QueryClient"))
    }

    @Test("query() with a QueryClient installed warns nothing")
    func happyPathIsSilent() {
        let component = Dummy()
        let client = QueryClient(clock: ManualClock())
        RenderObserverBox.current = client
        defer { RenderObserverBox.current = nil }
        let warns = capturingWarns {
            _ = component.query(IntQuery())
        }
        #expect(warns.isEmpty)
    }

    // MARK: - Value-type collision at read

    @Test("a cached value that fails the typed read fires the mismatch diagnostic")
    func valueTypeMismatchShouts() {
        let entry = QueryEntry()
        entry.value = "a string, not an Int"
        let diags = capturingDiagnostics {
            let state = makeSnapshot(from: entry, as: Int.self, key: ["collide"])
            #expect(state.data == nil)
        }
        #expect(diags.count == 1)
        #expect(diags[0].contains("type mismatch"))
        #expect(diags[0].contains("[\"collide\"]"))
        #expect(diags[0].contains("String"))
        #expect(diags[0].contains("Int"))
    }

    @Test("a matching typed read and an empty entry stay silent")
    func matchingReadIsSilent() {
        let entry = QueryEntry()
        entry.value = 7
        let diags = capturingDiagnostics {
            #expect(makeSnapshot(from: entry, as: Int.self).data == 7)
            #expect(makeSnapshot(from: QueryEntry(), as: Int.self).data == nil)   // no cached value: fine
        }
        #expect(diags.isEmpty)
    }

    // MARK: - Prefix-invalidate fanout

    private func seed(_ client: QueryClient, _ key: QueryKey, bag: OwnerBag) {
        let e = QueryEntry()
        e.boxedFetch = { 1 }
        e.value = 1
        e.lastFetched = .zero
        client.entries[key] = e
        let owner = AnyComponent(Dummy())
        bag.keep(owner)
        client.subscribe(owner: owner, scheduler: SyncScheduler { _ in }, to: key)
    }

    @Test("a prefix invalidate hitting >20 live entries warns with the count")
    func wideFanoutWarns() async {
        let client = QueryClient(clock: ManualClock())
        let bag = OwnerBag()
        for i in 0..<21 { seed(client, ["users", .int(i)], bag: bag) }
        let warns = capturingWarns {
            client.invalidate(["users"])
        }
        #expect(warns.count == 1)
        #expect(warns[0].contains("21 live entries"))
        #expect(warns[0].contains("[\"users\"]"))
        for t in client.inFlightTasks() { await t.value }
    }

    @Test("20 live entries, an exact invalidate, and unobserved entries stay quiet")
    func modestFanoutIsQuiet() async {
        let client = QueryClient(clock: ManualClock())
        let bag = OwnerBag()
        for i in 0..<20 { seed(client, ["users", .int(i)], bag: bag) }
        // 30 more cached-but-unsubscribed entries: they refetch lazily, not
        // as part of the storm, so they must not count.
        for i in 100..<130 {
            let e = QueryEntry()
            e.value = 1
            e.lastFetched = .zero
            client.entries[["users", .int(i)]] = e
        }
        let warns = capturingWarns {
            client.invalidate(["users"])
            client.invalidate(["users", 3], exact: true)
        }
        #expect(warns.isEmpty)
        for t in client.inFlightTasks() { await t.value }
    }
}
