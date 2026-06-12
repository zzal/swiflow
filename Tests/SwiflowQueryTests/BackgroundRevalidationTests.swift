// Tests/SwiflowQueryTests/BackgroundRevalidationTests.swift
import Testing
import Swiflow
@testable import SwiflowQuery

@Suite("Background/scaffold")
@MainActor
struct BackgroundScaffoldTests {
    @Test("Mount reconcile triggers exactly one initial fetch") func initialReconcileFetchesOnce() async {
        let bg = BG()
        await bg.settle()
        #expect(bg.probe.calls == 1)            // mount triggered one fetch
    }
}

@Suite("Background/polling")
@MainActor
struct BackgroundPollingTests {
    @Test("Polling refetches only once refetchInterval has fully elapsed") func pollFiresAtInterval() async {
        let bg = BG(refetchInterval: .seconds(5))
        await bg.settle()
        #expect(bg.probe.calls == 1)
        await bg.advance(.seconds(4))           // not yet due
        #expect(bg.probe.calls == 1)
        await bg.advance(.seconds(1))           // now 5s since last fetch → poll
        #expect(bg.probe.calls == 2)
    }
    @Test("Without a refetchInterval no poll ever fires") func noPollWithoutInterval() async {
        let bg = BG()                            // refetchInterval nil
        await bg.settle()
        await bg.advance(.seconds(9999))
        #expect(bg.probe.calls == 1)
    }
    @Test("A query that never succeeded does not poll — the deadline measures from last success") func neverSucceededDoesNotPoll() async {
        let bg = BG(refetchInterval: .seconds(5))
        bg.probe.failuresRemaining = 1           // initial fetch fails → lastFetched stays nil
        await bg.settle()
        #expect(bg.probe.calls == 1)
        await bg.advance(.seconds(5))            // poll branch requires lastFetched != nil
        #expect(bg.probe.calls == 1)             // retry is .none here, so no retry either
    }
}

@Suite("Background/retry")
@MainActor
struct BackgroundRetryTests {
    @Test("Failed fetch retries on the backoff schedule and resets retry state on success") func retriesWithBackoffThenSucceeds() async {
        let bg = BG(retry: RetryPolicy(maxRetries: 3, baseDelay: .seconds(1), maxDelay: .seconds(30)))
        bg.probe.failuresRemaining = 2           // fail #1 (initial), fail #2 (retry), then succeed
        await bg.settle()
        #expect(bg.probe.calls == 1)
        #expect(bg.entry.nextRetryDue == .seconds(1))   // scheduled at now(0) + backoff(0)
        await bg.advance(.seconds(1))            // retry #1 (fails)
        #expect(bg.probe.calls == 2)
        #expect(bg.entry.nextRetryDue == .seconds(3))   // now(1) + backoff(1)=2s
        await bg.advance(.seconds(2))            // retry #2 (succeeds)
        #expect(bg.probe.calls == 3)
        #expect(bg.entry.nextRetryDue == nil)           // reset on success
        #expect(bg.entry.failureCount == 0)
    }
    @Test("Retries stop after maxRetries with nothing further scheduled") func stopsAfterMaxRetries() async {
        let bg = BG(retry: RetryPolicy(maxRetries: 2, baseDelay: .seconds(1), maxDelay: .seconds(30)))
        bg.probe.failuresRemaining = 99          // always fails
        await bg.settle()                        // attempt 1
        await bg.advance(.seconds(1))            // retry 1
        await bg.advance(.seconds(2))            // retry 2
        #expect(bg.probe.calls == 3)             // 1 + 2 retries
        #expect(bg.entry.nextRetryDue == nil)    // exhausted — no further schedule
        await bg.advance(.seconds(60))
        #expect(bg.probe.calls == 3)             // no more attempts
    }
}

@Suite("Background/focus")
@MainActor
struct BackgroundFocusTests {
    @Test("Focus refetches only entries that have gone stale") func focusRefetchesStaleOnly() async {
        let bg = BG(staleTime: .seconds(10))
        await bg.settle()                        // fetch #1 at t=0
        bg.clock.advance(by: .seconds(5))        // still fresh (<10s)
        await bg.focus()
        #expect(bg.probe.calls == 1)             // fresh → skipped
        bg.clock.advance(by: .seconds(6))        // now 11s → stale
        await bg.focus()
        #expect(bg.probe.calls == 2)             // stale → refetched
    }
    @Test("refetchOnFocus: false suppresses the focus refetch even when stale") func focusSkipsWhenOptedOut() async {
        let bg = BG(staleTime: .zero, refetchOnFocus: false)  // always stale, but opted out
        await bg.settle()
        await bg.focus()
        #expect(bg.probe.calls == 1)
    }
    @Test("Back-to-back focus events coalesce into a single refetch") func doubleFocusCoalesces() async {
        let bg = BG(staleTime: .zero)            // staleTime .zero → stale immediately after a fetch
        await bg.settle()                        // fetch #1 done
        bg.client.focusChanged(visible: true)    // spawns fetch #2 (in-flight, not awaited)
        bg.client.focusChanged(visible: true)    // inFlight != nil → no cancel/respawn
        await bg.settle()
        #expect(bg.probe.calls == 2)             // exactly one refetch, not two
    }
}

@Suite("Background/supersede")
@MainActor
struct BackgroundSupersedeTests {
    @Test("invalidate clears a pending retry synchronously, before its refetch settles") func invalidateClearsPendingRetry() async {
        let bg = BG(retry: RetryPolicy(maxRetries: 3, baseDelay: .seconds(5), maxDelay: .seconds(30)))
        bg.probe.failuresRemaining = 1           // initial fetch fails → schedules retry at t=5
        await bg.settle()
        #expect(bg.entry.nextRetryDue == .seconds(5))
        #expect(bg.entry.failureCount == 1)
        bg.client.invalidate(["k"])              // forceStaleAndRefetch → reset SYNCHRONOUSLY, then refetch
        // Assert the reset BEFORE the refetch settles — otherwise a passing
        // assertion could come from the refetch's own commitFetch success, not
        // the §5.5 reset in forceStaleAndRefetch (which is what we're guarding).
        #expect(bg.entry.nextRetryDue == nil)    // pending retry cleared at supersede time
        #expect(bg.entry.failureCount == 0)
        await bg.settle()
        #expect(bg.entry.nextRetryDue == nil)    // still clear after the refetch settles
    }
    @Test("setQueryData clears a pending retry and resets failureCount") func setQueryDataClearsPendingRetry() async {
        let bg = BG(retry: RetryPolicy(maxRetries: 3, baseDelay: .seconds(5), maxDelay: .seconds(30)))
        bg.probe.failuresRemaining = 1
        await bg.settle()
        #expect(bg.entry.nextRetryDue == .seconds(5))
        bg.client.setQueryData(["k"], ["optimistic"])
        #expect(bg.entry.nextRetryDue == nil)
        #expect(bg.entry.failureCount == 0)
    }
}

@Suite("Background/poll+retry")
@MainActor
struct BackgroundPollRetryTests {
    /// A polling query whose poll fails enters the retry cycle; once retries are
    /// exhausted it resumes polling (failures never update `lastFetched`, so the
    /// poll deadline still measures from the last success).
    @Test("A failed poll enters the retry cycle, then polling resumes once retries exhaust") func failedPollRetriesThenResumesPolling() async {
        let bg = BG(refetchInterval: .seconds(5),
                    retry: RetryPolicy(maxRetries: 1, baseDelay: .seconds(1), maxDelay: .seconds(30)))
        await bg.settle()                         // fetch #1 succeeds at t=0
        #expect(bg.probe.calls == 1)

        bg.probe.failuresRemaining = 2            // the upcoming poll + its one retry both fail
        await bg.advance(.seconds(5))             // t=5: poll fires → fails → retry scheduled at t=6
        #expect(bg.probe.calls == 2)
        #expect(bg.entry.nextRetryDue == .seconds(6))
        await bg.advance(.seconds(1))             // t=6: retry fires → fails → maxRetries(1) reached
        #expect(bg.probe.calls == 3)
        #expect(bg.entry.nextRetryDue == nil)     // retries exhausted, not stuck

        await bg.advance(.seconds(1))             // t=7: poll resumes (7-0 >= 5) → fetch #4 succeeds
        #expect(bg.probe.calls == 4)
        #expect(bg.entry.nextRetryDue == nil)
    }
}
