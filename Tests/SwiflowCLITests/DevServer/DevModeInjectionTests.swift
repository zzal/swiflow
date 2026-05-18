// Tests/SwiflowCLITests/DevServer/DevModeInjectionTests.swift
import Testing
@testable import SwiflowCLI

@Suite("DevModeInjection")
struct DevModeInjectionTests {

    @Test("Injects window.SWIFLOW_DEV=true immediately before the driver tag")
    func injectsBeforeDriverTag() {
        let input = """
        <html><body>
        <div id="app"></div>
        <script src="swiflow-driver.js"></script>
        <script type="module">import { init } from "./x.js"; await init();</script>
        </body></html>
        """
        let output = DevModeInjection.injectDevSignal(into: input)
        #expect(output.contains("window.SWIFLOW_DEV=true"))
        // The injected script must come BEFORE the driver tag so the
        // global is set when the driver IIFE runs.
        let injectedIdx = output.range(of: "window.SWIFLOW_DEV=true")!.lowerBound
        let driverIdx = output.range(of: "swiflow-driver.js")!.lowerBound
        #expect(injectedIdx < driverIdx)
    }

    @Test("Falls back to injecting before </body> if no driver tag present")
    func fallsBackToBody() {
        let input = "<html><body><div>nothing here</div></body></html>"
        let output = DevModeInjection.injectDevSignal(into: input)
        #expect(output.contains("window.SWIFLOW_DEV=true"))
        let injectedIdx = output.range(of: "window.SWIFLOW_DEV=true")!.lowerBound
        let bodyCloseIdx = output.range(of: "</body>")!.lowerBound
        #expect(injectedIdx < bodyCloseIdx)
    }

    @Test("Returns input unchanged when HTML has neither driver tag nor </body>")
    func malformedPassesThrough() {
        let input = "<html><div>broken</div>"
        let output = DevModeInjection.injectDevSignal(into: input)
        #expect(output == input)
    }

    @Test("Injects only once, even if called on already-injected HTML")
    func idempotent() {
        let input = """
        <body><script src="swiflow-driver.js"></script></body>
        """
        let once = DevModeInjection.injectDevSignal(into: input)
        let twice = DevModeInjection.injectDevSignal(into: once)
        // Count occurrences of the marker
        let count = twice.components(separatedBy: "window.SWIFLOW_DEV=true").count - 1
        #expect(count == 1)
    }
}
