// Tests/SwiflowCLITests/DriverEmbedderTests.swift
import Foundation
import Testing
@testable import SwiflowCLI

@Suite("Driver embedding")
struct DriverEmbedderTests {

    @Test("DriverEmbedder.swiftSource wraps the JS source in a Swift String constant")
    func wrapsJSAsSwiftConstant() {
        let js = "console.log('hello');"
        let generated = DriverEmbedder.swiftSource(forJSSource: js)
        #expect(generated.contains("// GENERATED FILE — do not edit."))
        #expect(generated.contains("enum EmbeddedDriver"))
        #expect(generated.contains("static let javascriptSource: String"))
        // The JS source must appear verbatim somewhere in the output.
        #expect(generated.contains(js))
    }

    @Test("EmbeddedDriver.javascriptSource matches js-driver/swiflow-driver.js verbatim")
    func embeddedDriverIsFresh() throws {
        // Resolve js-driver/swiflow-driver.js relative to this test file so
        // the test works from any CWD.
        let testFile = URL(fileURLWithPath: #filePath)
        let repoRoot = testFile
            .deletingLastPathComponent()  // SwiflowCLITests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
        let driverURL = repoRoot.appendingPathComponent("js-driver/swiflow-driver.js")

        let onDiskJS = try String(contentsOf: driverURL, encoding: .utf8)
        #expect(EmbeddedDriver.javascriptSource == onDiskJS, """
            EmbeddedDriver is stale. Regenerate by running:
                swift scripts/embed-driver.swift
            from the repo root, then commit Sources/SwiflowCLI/EmbeddedDriver.swift.
            """)
    }
}
