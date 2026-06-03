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
