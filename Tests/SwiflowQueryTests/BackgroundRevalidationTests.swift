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
