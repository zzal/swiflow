// Tests/SwiflowQueryTests/QueryClientHardeningTests.swift
// Pre-launch audit Wave-1 #5/#6 regression gates — the two interleavings the
// steady-state convergence fuzz cannot reach (its model has no eviction+recycle
// and no polling-under-persistent-failure; see docs/reviews/2026-07-01-pre-launch-audit.md).
import Testing
import Swiflow
@testable import SwiflowQuery

@MainActor private final class HardeningDummy: Component { var body: VNode { .text("") } }

@MainActor private final class Gate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var opened = false
    func wait() async {
        if opened { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func open() {
        opened = true
        continuation?.resume()
        continuation = nil
    }
}

@Suite("QueryClient hardening — eviction recycling")
@MainActor
struct EntryRecyclingTests {

    @Test("a zombie fetch from an evicted entry cannot overwrite the recycled entry's fresh value")
    func zombieFetchDropped() async {
        let clock = ManualClock()
        let client = QueryClient(clock: clock)
        let owner1 = AnyComponent(HardeningDummy())
        let gate = Gate()
        var calls = 0

        func observation() -> QueryClient.QueryObservation {
            QueryClient.QueryObservation(
                key: ["k"], tags: [], staleTime: .zero,
                refetchInterval: nil, refetchOnFocus: false, retry: .none,
                gcTime: .seconds(5),
                boxedFetch: {
                    calls += 1
                    if calls == 1 {
                        await gate.wait()      // park fetch #1 (cancel is cooperative
                        return "stale"          // and this gate ignores it — models an
                    }                            // un-abortable in-flight HTTP fetch)
                    return "fresh"
                })
        }

        // Fetch #1 starts on entry E1 and parks.
        client.reconcile(owner: owner1, scheduler: SyncScheduler { _ in },
                         observations: [observation()])
        while calls < 1 { await Task.yield() }

        // Unmount → unobserved → gcTime passes → tick evicts E1 (cancelling
        // fetch #1 cooperatively — it stays parked, still running).
        client.dropComponent(owner1)
        client.tick(now: clock.now())                 // stamps unobservedSince
        clock.advance(by: .seconds(6))
        client.tick(now: clock.now())                 // evicts E1

        // Remount: a brand-new entry E2 for the same key; fetch #2 commits fresh.
        let owner2 = AnyComponent(HardeningDummy())
        client.reconcile(owner: owner2, scheduler: SyncScheduler { _ in },
                         observations: [observation()])
        while (client.getQueryDataErased(["k"]) as? String) != "fresh" { await Task.yield() }

        // Release the zombie. Its generation (0) numerically matches E2's (0) —
        // only entry identity distinguishes them.
        gate.open()
        for _ in 0..<20 { await Task.yield() }

        #expect(client.getQueryDataErased(["k"]) as? String == "fresh",
                "an evicted entry's zombie fetch must not overwrite the recycled entry's value")
    }
}

@Suite("QueryClient hardening — polling under persistent failure")
@MainActor
struct PollRetryStormTests {

    @Test("exhausted retries: polling resumes at the interval, not every tick")
    func exhaustedRetriesPollAtInterval() async {
        let bg = BG(refetchInterval: .seconds(60),
                    retry: RetryPolicy(maxRetries: 1, baseDelay: .seconds(1), maxDelay: .seconds(1)))
        await bg.settle()
        #expect(bg.probe.calls == 1)          // initial fetch succeeded → lastFetched set

        // Server goes down: the next poll fails, its single retry fails → exhausted.
        bg.probe.failuresRemaining = .max
        await bg.advance(.seconds(60))        // poll → attempt 2 fails, retry scheduled
        #expect(bg.probe.calls == 2)
        await bg.advance(.seconds(1))         // retry → attempt 3 fails, retries exhausted
        #expect(bg.probe.calls == 3)

        // THE STORM (pre-fix): every tick within the interval spawned an attempt.
        await bg.advance(.seconds(1))
        await bg.advance(.seconds(1))
        await bg.advance(.seconds(1))
        #expect(bg.probe.calls == 3,
                "no attempts between polls once retries are exhausted (was: one per tick)")

        // A full interval after the last ATTEMPT, polling resumes with one attempt.
        await bg.advance(.seconds(60))
        #expect(bg.probe.calls == 4, "polling resumes at the interval after exhaustion")
    }

    @Test("a scheduled retry owns the next attempt: polls do not double-dip during backoff")
    func pollWaitsForScheduledRetry() async {
        // Interval SHORTER than the retry backoff — the poll must not jump the queue.
        let bg = BG(refetchInterval: .seconds(2),
                    retry: RetryPolicy(maxRetries: 3, baseDelay: .seconds(10), maxDelay: .seconds(10)))
        await bg.settle()
        #expect(bg.probe.calls == 1)          // initial success

        bg.probe.failuresRemaining = 1
        await bg.advance(.seconds(2))         // poll → attempt 2 fails → retry due in 10s
        #expect(bg.probe.calls == 2)

        await bg.advance(.seconds(2))         // interval elapsed, but a retry is scheduled
        await bg.advance(.seconds(2))
        #expect(bg.probe.calls == 2, "the poll must not fire while a retry is scheduled")

        await bg.advance(.seconds(6))         // t reaches the retry due (10s after failure)
        #expect(bg.probe.calls == 3, "the scheduled retry fires (and succeeds)")
        #expect(bg.entry.error == nil)
    }

    @Test("focus refetch does not jump a scheduled retry's backoff")
    func focusRespectsScheduledRetry() async {
        let bg = BG(staleTime: .zero,
                    retry: RetryPolicy(maxRetries: 3, baseDelay: .seconds(10), maxDelay: .seconds(10)))
        // Make the INITIAL fetch fail so a retry is scheduled.
        // (BG's init already fired it — so instead: succeed first, then fail a poll-less refetch on focus.)
        await bg.settle()
        #expect(bg.probe.calls == 1)

        bg.probe.failuresRemaining = .max
        await bg.focus()                       // staleTime zero → focus refetch → fails → retry in 10s
        #expect(bg.probe.calls == 2)

        await bg.advance(.seconds(1))          // 1s < backoff; nothing due
        await bg.focus()                       // pre-fix: needsFetch(true) → attempt jumps the backoff
        #expect(bg.probe.calls == 2, "focus must not spawn an attempt while a retry is scheduled")
    }
}
