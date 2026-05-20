// Tests/SwiflowCLITests/DevServer/DevModeInjectionHMRTests.swift
//
// Verifies the dev-mode injector ships `window.SWIFLOW_DEV=true`.
// The existing DevModeInjectionTests cover placement/fallback/idempotency;
// this file covers idempotency with the current marker string.
import Testing
@testable import SwiflowCLI

@Suite("DevModeInjection HMR signal")
struct DevModeInjectionHMRTests {

    @Test("injectDevSignal injects SWIFLOW_DEV=true")
    func injectsDevSignal() {
        let html = #"""
        <html><body>
          <div id="app"></div>
          <script src="swiflow-driver.js"></script>
        </body></html>
        """#
        let result = DevModeInjection.injectDevSignal(into: html)
        #expect(result.contains("window.SWIFLOW_DEV=true"))
    }

    @Test("injection is idempotent on second application")
    func idempotent() {
        let html = #"<html><body><script src="swiflow-driver.js"></script></body></html>"#
        let once = DevModeInjection.injectDevSignal(into: html)
        let twice = DevModeInjection.injectDevSignal(into: once)
        #expect(once == twice)
        let occurrences = once.components(separatedBy: "SWIFLOW_DEV=true").count - 1
        #expect(occurrences == 1)
    }
}
