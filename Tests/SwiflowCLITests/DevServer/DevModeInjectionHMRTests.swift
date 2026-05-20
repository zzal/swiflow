// Tests/SwiflowCLITests/DevServer/DevModeInjectionHMRTests.swift
//
// Phase 8 — verifies the dev-mode injector now ships BOTH
// `window.SWIFLOW_DEV=true` and `window.SWIFLOW_HMR=true`. The
// existing DevModeInjectionTests cover the original DEV signal
// and the placement/fallback/idempotency mechanics; this file
// focuses narrowly on the HMR addition so a regression localizes
// quickly.
import Testing
@testable import SwiflowCLI

@Suite("DevModeInjection HMR signal")
struct DevModeInjectionHMRTests {

    @Test("injectDevSignal also injects SWIFLOW_HMR=true")
    func injectsHMRSignal() {
        let html = #"""
        <html><body>
          <div id="app"></div>
          <script src="swiflow-driver.js"></script>
        </body></html>
        """#
        let result = DevModeInjection.injectDevSignal(into: html)
        #expect(result.contains("window.SWIFLOW_DEV=true"))
        #expect(result.contains("window.SWIFLOW_HMR=true"))
    }

    @Test("injection is idempotent on second application")
    func idempotent() {
        let html = #"<html><body><script src="swiflow-driver.js"></script></body></html>"#
        let once = DevModeInjection.injectDevSignal(into: html)
        let twice = DevModeInjection.injectDevSignal(into: once)
        #expect(once == twice)
        // The marker should appear exactly once in the output.
        let occurrences = once.components(separatedBy: "SWIFLOW_HMR=true").count - 1
        #expect(occurrences == 1)
    }
}
