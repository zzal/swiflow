// Tests/SwiflowQueryTests/BackgroundRevalidationTests.swift
import Testing
import Swiflow
@testable import SwiflowQuery

@Suite("Background/scaffold")
@MainActor
struct BackgroundScaffoldTests {
    @Test func initialReconcileFetchesOnce() async {
        let bg = BG()
        await bg.settle()
        #expect(bg.probe.calls == 1)            // mount triggered one fetch
    }
}

@Suite("Background/polling")
@MainActor
struct BackgroundPollingTests {
    @Test func pollFiresAtInterval() async {
        let bg = BG(refetchInterval: .seconds(5))
        await bg.settle()
        #expect(bg.probe.calls == 1)
        await bg.advance(.seconds(4))           // not yet due
        #expect(bg.probe.calls == 1)
        await bg.advance(.seconds(1))           // now 5s since last fetch → poll
        #expect(bg.probe.calls == 2)
    }
    @Test func noPollWithoutInterval() async {
        let bg = BG()                            // refetchInterval nil
        await bg.settle()
        await bg.advance(.seconds(9999))
        #expect(bg.probe.calls == 1)
    }
    @Test func neverSucceededDoesNotPoll() async {
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
    @Test func retriesWithBackoffThenSucceeds() async {
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
    @Test func stopsAfterMaxRetries() async {
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
