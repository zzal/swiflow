// Tests/SwiflowCLITests/DoctorReportTests.swift
import Testing
@testable import SwiflowCLI

@Suite struct DoctorReportTests {

    @Test("Missing wasm-opt fails the report and names binaryen in the summary") func failsWhenWasmOptMissing() {
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

    @Test("Missing swift.org toolchain fails the report") func failsWhenMacToolchainMissing() {
        let report = DoctorReport(
            swift: .found("Swift 6.3"),
            wasmSDK: .found("6.3-RELEASE_wasm"),
            macToolchain: .missing,
            wasmOpt: .found("version 118")
        )
        #expect(report.exitCode == 1)
        #expect(report.summary.contains("swift.org toolchain"))
    }

    @Test("An incompatible wasm-sdk fails the report and prints the remediation") func failsWhenWasmSDKIncompatible() {
        let report = DoctorReport(
            swift: .found("Apple Swift version 6.3.2"),
            wasmSDK: .incompatible(
                detail: "swift-6.3-RELEASE_wasm is built for Swift 6.3, but your compiler is 6.3.2",
                hint: "The WASM SDK must match your compiler exactly.\n  swift sdk remove swift-6.3-RELEASE_wasm"
            ),
            macToolchain: nil,
            wasmOpt: .found("version 129")
        )
        #expect(report.exitCode == 1)
        #expect(report.summary.contains("✗ wasm-sdk"))
        #expect(report.summary.contains("but your compiler is 6.3.2"))
        #expect(report.summary.contains("swift sdk remove"))
    }

    @Test("A nil macToolchain row (Linux) is excluded from the report and the exit code") func macToolchainNotApplicableDoesNotFail() {
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
