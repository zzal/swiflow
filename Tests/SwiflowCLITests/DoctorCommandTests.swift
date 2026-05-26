// Tests/SwiflowCLITests/DoctorCommandTests.swift
import Testing
import Foundation
@testable import SwiflowCLI

@Suite("DoctorCommand")
struct DoctorCommandTests {
    @Test("Reports all-green when every required tool is on PATH")
    func allPresent() throws {
        let report = DoctorReport(
            swift: .found("Apple Swift version 6.3"),
            wasmSDK: .found("6.3-RELEASE-wasm")
        )
        #expect(report.exitCode == 0)
        #expect(report.summary.contains("✓ swift"))
        #expect(report.summary.contains("✓ wasm-sdk"))
        #expect(!report.summary.contains("✗"))
    }

    @Test("Exit non-zero and prints install hint when wasm-sdk missing")
    func wasmSDKMissing() throws {
        let report = DoctorReport(
            swift: .found("Apple Swift version 6.3"),
            wasmSDK: .missing
        )
        #expect(report.exitCode == 1)
        #expect(report.summary.contains("✗ wasm-sdk"))
        #expect(report.summary.contains("swift sdk install"))
    }

    @Test("Each tool reports independently — swift missing listed")
    func multipleMissing() throws {
        let report = DoctorReport(
            swift: .missing,
            wasmSDK: .missing
        )
        #expect(report.exitCode == 1)
        #expect(report.summary.contains("✗ swift"))
        #expect(report.summary.contains("✗ wasm-sdk"))
        #expect(report.summary.contains("swift.org/install"))
        #expect(report.summary.contains("swift sdk install"))
    }
}
