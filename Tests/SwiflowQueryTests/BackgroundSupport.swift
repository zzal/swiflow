// Tests/SwiflowQueryTests/BackgroundSupport.swift
import Testing
import Swiflow
@testable import SwiflowQuery

@MainActor final class BGDummy: Component { var body: VNode { .text("") } }

/// A controllable fetch: counts calls; the next `failuresRemaining` calls throw.
@MainActor final class FetchProbe {
    var calls = 0
    var failuresRemaining = 0
    enum Boom: Error { case fail }
    func run() async throws -> [String] {
        calls += 1
        if failuresRemaining > 0 { failuresRemaining -= 1; throw Boom.fail }
        return ["v\(calls)"]
    }
}

/// One live query observation wired to a `ManualClock`, with helpers to drive
/// background triggers deterministically.
@MainActor final class BG {
    let clock = ManualClock()
    let client: QueryClient
    let owner = AnyComponent(BGDummy())
    let probe = FetchProbe()

    init(staleTime: Duration = .seconds(9999),
         refetchInterval: Duration? = nil,
         refetchOnFocus: Bool = true,
         retry: RetryPolicy = .none) {
        client = QueryClient(clock: clock)
        let probe = self.probe
        client.reconcile(
            owner: owner,
            scheduler: SyncScheduler { _ in },
            observations: [QueryClient.QueryObservation(
                key: ["k"], tags: [], staleTime: staleTime,
                refetchInterval: refetchInterval, refetchOnFocus: refetchOnFocus, retry: retry,
                boxedFetch: { try await probe.run() })])
    }

    func settle() async { for t in client.inFlightTasks() { await t.value } }
    /// Advance the clock, tick, and drain resulting fetches.
    func advance(_ d: Duration) async { clock.advance(by: d); client.tick(now: clock.now()); await settle() }
    func focus() async { client.focusChanged(visible: true); await settle() }
    var entry: QueryEntry { client.entries[["k"]]! }
}

/// Serializes tests that install `_swiflowDiagnosticOverride` across an await.
/// The override is a process global; the repo convention is that override
/// users stay synchronous (no interleaving on the main actor) — but a test
/// whose diagnostic fires inside an async path (`finish`, a parked fetch)
/// must hold the override across a suspension, where a parallel suite's
/// install/restore would clobber it. Acquire around the whole install→assert
/// span; release in a defer.
@MainActor final class DiagnosticOverrideLock {
    static let shared = DiagnosticOverrideLock()
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func acquire() async {
        while busy { await withCheckedContinuation { waiters.append($0) } }
        busy = true
    }
    func release() {
        busy = false
        if !waiters.isEmpty { waiters.removeFirst().resume() }
    }
}
