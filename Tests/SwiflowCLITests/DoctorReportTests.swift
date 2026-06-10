// Tests/SwiflowCLITests/DoctorReportTests.swift
import Testing
@testable import SwiflowCLI

@Suite struct DoctorReportTests {

    @Test func failsWhenWasmOptMissing() {
        let report = DoctorReport(
            swift: .found("Swift 6.3"),
            wasmSDK: .found("6.3-RELEASE_wasm"),
            macToolchain: .found("org.swift.630"),
            wasmOpt: .missing
        )
        #expect(report.exitCode == 1)
        #expect(report.summary.contains("wasm-opt"))
        #expect(report.summary.contains("binaryen"))
    }

    @Test func failsWhenMacToolchainMissing() {
        let report = DoctorReport(
            swift: .found("Swift 6.3"),
            wasmSDK: .found("6.3-RELEASE_wasm"),
            macToolchain: .missing,
            wasmOpt: .found("version 118")
        )
        #expect(report.exitCode == 1)
        #expect(report.summary.contains("swift.org toolchain"))
    }

    @Test func macToolchainNotApplicableDoesNotFail() {
        // Linux: the macOS toolchain row is nil — absent from the report
        // and excluded from the exit code.
        let report = DoctorReport(
            swift: .found("Swift 6.3"),
            wasmSDK: .found("6.3-RELEASE_wasm"),
            macToolchain: nil,
            wasmOpt: .found("version 118")
        )
        #expect(report.exitCode == 0)
        #expect(!report.summary.contains("mac-toolchain"))
    }
}
