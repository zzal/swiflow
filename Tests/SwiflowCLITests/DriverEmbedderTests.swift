// Tests/SwiflowCLITests/DriverEmbedderTests.swift
import Foundation
import Testing
@testable import SwiflowCLI

@Suite("Driver embedding")
struct DriverEmbedderTests {

    @Test("DriverEmbedder.swiftSource wraps all eight JS sources as Swift constants")
    func wrapsJSAsSwiftConstant() {
        let g = DriverEmbedder.swiftSource(
            driverJS: "DRIVER", driverJSMinified: "DRIVERMIN",
            swJS: "SW", swJSMinified: "SWMIN",
            regionsJS: "REGIONS", regionsJSMinified: "REGIONSMIN",
            guestSdkJS: "GUEST", guestSdkJSMinified: "GUESTMIN"
        )
        for name in ["javascriptSource", "javascriptSourceMinified",
                     "serviceWorkerSource", "serviceWorkerSourceMinified",
                     "regionsSource", "regionsSourceMinified",
                     "guestSdkSource", "guestSdkSourceMinified"] {
            #expect(g.contains("static let \(name): String"))
        }
        for body in ["DRIVER", "DRIVERMIN", "SW", "SWMIN", "REGIONS", "REGIONSMIN", "GUEST", "GUESTMIN"] {
            #expect(g.contains(body))
        }
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

    // The byte-pin (audit III Wave-1 #5): the codegen script re-implements
    // DriverEmbedder.swiftSource inline (it runs standalone, no SPM context)
    // and its comment promises a freshness test catches drift between the
    // two — this is that test. Feeding the compiled constants back in makes
    // it a pure FORMAT pin, mirroring TemplateEmbedderTests' byte-pin of the
    // twin embedder: if either emitter's wrapper (header, constant order,
    // delimiters, whitespace) changes without the other, the reconstruction
    // stops matching the tracked file. Content freshness is covered
    // elsewhere — readable sources by the four verbatim tests below,
    // minified bytes by CI's embed-freshness job (the one gate that can run
    // esbuild). The three gates compose to full coverage.
    @Test("EmbeddedDriver.swift is bit-for-bit what DriverEmbedder.swiftSource would produce")
    func embeddedDriverFileMatchesDriverEmbedderOutput() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let repoRoot = testFile
            .deletingLastPathComponent()  // SwiflowCLITests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
        let embeddedURL = repoRoot.appendingPathComponent("Sources/SwiflowCLI/EmbeddedDriver.swift")

        let actual = try String(contentsOf: embeddedURL, encoding: .utf8)
        let expected = DriverEmbedder.swiftSource(
            driverJS: EmbeddedDriver.javascriptSource,
            driverJSMinified: EmbeddedDriver.javascriptSourceMinified,
            swJS: EmbeddedDriver.serviceWorkerSource,
            swJSMinified: EmbeddedDriver.serviceWorkerSourceMinified,
            regionsJS: EmbeddedDriver.regionsSource,
            regionsJSMinified: EmbeddedDriver.regionsSourceMinified,
            guestSdkJS: EmbeddedDriver.guestSdkSource,
            guestSdkJSMinified: EmbeddedDriver.guestSdkSourceMinified
        )
        #expect(actual == expected, """
            EmbeddedDriver.swift no longer matches DriverEmbedder.swiftSource \
            output — the emit format in scripts/embed-driver.swift and \
            DriverEmbedder.swiftSource has drifted apart. Align the two \
            emitters, then regenerate (from the repo root):
                swift scripts/embed-driver.swift
            and commit Sources/SwiflowCLI/EmbeddedDriver.swift.
            """)
    }

    @Test("EmbeddedDriver contains dev error handler and RAF shim")
    func containsDevErrorHandlerAndRAFShim() {
        #expect(EmbeddedDriver.javascriptSource.contains("__swiflowDevError"))
        #expect(EmbeddedDriver.javascriptSource.contains("[swiflow dev] For Swift source locations"))
        #expect(EmbeddedDriver.javascriptSource.contains("goo.gle/wasm-debugging-extension"))
    }

    @Test("EmbeddedDriver.regionsSource matches js-driver/swiflow-regions.js verbatim")
    func regionsSourceIsFresh() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let repoRoot = testFile.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = repoRoot.appendingPathComponent("js-driver/swiflow-regions.js")
        let onDisk = try String(contentsOf: url, encoding: .utf8)
        #expect(EmbeddedDriver.regionsSource == onDisk,
                "Run `swift scripts/embed-driver.swift` to regenerate EmbeddedDriver.swift")
    }

    @Test("EmbeddedDriver.guestSdkSource matches js-driver/swiflow-region-guest.js verbatim")
    func guestSdkSourceIsFresh() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let repoRoot = testFile.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = repoRoot.appendingPathComponent("js-driver/swiflow-region-guest.js")
        let onDisk = try String(contentsOf: url, encoding: .utf8)
        #expect(EmbeddedDriver.guestSdkSource == onDisk,
                "Run `swift scripts/embed-driver.swift` to regenerate EmbeddedDriver.swift")
    }

    @Test("EmbeddedDriver.serviceWorkerSource matches js-driver/swiflow-service-worker.js verbatim")
    func swSourceIsFresh() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let repoRoot = testFile
            .deletingLastPathComponent()  // SwiflowCLITests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
        let path = repoRoot.appendingPathComponent("js-driver/swiflow-service-worker.js")
        let onDisk = try String(contentsOf: path, encoding: .utf8)
        #expect(EmbeddedDriver.serviceWorkerSource == onDisk,
                "Run `swift scripts/embed-driver.swift` to regenerate EmbeddedDriver.swift")
    }

    @Test("minified constants are non-empty, shorter, and collapsed to one line")
    func minifiedConstantsLookMinified() {
        for (readable, min) in [
            (EmbeddedDriver.javascriptSource, EmbeddedDriver.javascriptSourceMinified),
            (EmbeddedDriver.serviceWorkerSource, EmbeddedDriver.serviceWorkerSourceMinified),
            (EmbeddedDriver.regionsSource, EmbeddedDriver.regionsSourceMinified),
            (EmbeddedDriver.guestSdkSource, EmbeddedDriver.guestSdkSourceMinified),
        ] {
            #expect(!min.isEmpty)
            #expect(min.utf8.count < readable.utf8.count)
            // Minified output is very few lines (esbuild collapses most to one,
            // but template literals with embedded newlines keep their newlines).
            #expect(min.split(separator: "\n").count <= 10)
        }
    }

    @Test("minified service worker keeps the build-tag placeholder for stamping")
    func minifiedSWKeepsBuildTagPlaceholder() {
        #expect(EmbeddedDriver.serviceWorkerSourceMinified.contains("__SWIFLOW_BUILD_TAG__"))
    }
}
