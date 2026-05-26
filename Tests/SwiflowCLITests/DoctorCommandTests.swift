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
            wasmSDK: .found("6.3-RELEASE-wasm"),
            wasmOpt: .found("wasm-opt version 116")
        )
        #expect(report.exitCode == 0)
        #expect(report.summary.contains("✓ swift"))
        #expect(report.summary.contains("✓ wasm-opt"))
        #expect(!report.summary.contains("✗"))
    }

    @Test("Exit non-zero and prints install hint when wasm-opt missing")
    func wasmOptMissing() throws {
        let report = DoctorReport(
            swift: .found("Apple Swift version 6.3"),
            wasmSDK: .found("6.3-RELEASE-wasm"),
            wasmOpt: .missing
        )
        #expect(report.exitCode == 1)
        #expect(report.summary.contains("✗ wasm-opt"))
        #expect(report.summary.contains("brew install binaryen"))
    }

    @Test("Each tool reports independently — multiple misses listed")
    func multipleMissing() throws {
        let report = DoctorReport(
            swift: .found("Apple Swift version 6.3"),
            wasmSDK: .missing,
            wasmOpt: .missing
        )
        #expect(report.exitCode == 1)
        #expect(report.summary.contains("✗ wasm-sdk"))
        #expect(report.summary.contains("✗ wasm-opt"))
        #expect(report.summary.contains("swift sdk install"))
        #expect(report.summary.contains("brew install binaryen"))
    }
}
