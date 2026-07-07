// Tests/SwiflowCLITests/DoctorProbeTests.swift
//
// Audit III Wave-2 #8: doctor must go through the real probes. Doctor used
// to re-implement toolchain probing with a private raw-Process helper,
// bypassing the ProcessRunner seam — untestable by construction, and
// ALREADY DIVERGED from the build path in two ways this suite pins shut:
//
//   1. SDK filter: doctor kept any id `.contains("wasm")` while the build
//      path requires `.hasSuffix("_wasm")` (WasmSDKProbe.parseSDKList) —
//      doctor could bless an SDK the build then rejects.
//   2. swift resolution: doctor ran bare `env swift` while build resolves
//      through SwiftExecutableLocator (`which swift`) — doctor could report
//      a different compiler than the one build actually runs.
//
// These tests drive DoctorCommand.makeReport(using:) with a scripted
// runner, the way every other command's orchestration is tested.
import Foundation
import Testing
@testable import SwiflowCLI

/// Closure-scripted ProcessRunner that also records every call, so tests
/// can assert BOTH what doctor concluded and which probes it consulted.
private final class ScriptedProcessRunner: ProcessRunner {
    struct Call {
        let executable: URL
        let arguments: [String]
    }
    private(set) var calls: [Call] = []
    private let script: (URL, [String]) -> ProcessResult

    init(script: @escaping (URL, [String]) -> ProcessResult) {
        self.script = script
    }

    func run(
        executable: URL,
        arguments: [String],
        workingDirectory: URL?,
        environment: [String: String]?,
        captureOutput: Bool
    ) throws -> ProcessResult {
        calls.append(Call(executable: executable, arguments: arguments))
        return script(executable, arguments)
    }
}

private func ok(_ stdout: String) -> ProcessResult {
    ProcessResult(exitCode: 0, standardOutput: stdout, standardError: nil)
}
private let notFound = ProcessResult(exitCode: 127, standardOutput: nil, standardError: nil)

/// A fully healthy toolchain, overridable per test.
private func healthyRunner(
    whichSwift: ProcessResult = ok("/toolchains/bin/swift\n"),
    versionLine: String = "Apple Swift version 6.3.2 (swift-6.3.2-RELEASE)",
    sdkList: ProcessResult = ok("swift-6.3.2-RELEASE_wasm\n"),
    wasmOpt: ProcessResult = ok("wasm-opt version 118 (version_118)\n")
) -> ScriptedProcessRunner {
    ScriptedProcessRunner { _, args in
        if args == ["which", "swift"] { return whichSwift }
        if args == ["--version"] { return ok(versionLine + "\nTarget: arm64-apple-macosx14.0\n") }
        if args == ["sdk", "list"] { return sdkList }
        if args == ["wasm-opt", "--version"] { return wasmOpt }
        return notFound
    }
}

@Suite("Doctor probes through the real seams")
struct DoctorProbeTests {

    @Test("a healthy toolchain reports every row found and exits 0")
    func healthyToolchain() {
        let report = DoctorCommand.makeReport(using: healthyRunner(), macToolchain: nil)
        #expect(report.exitCode == 0)
        if case .found(let sdk) = report.wasmSDK {
            #expect(sdk == "swift-6.3.2-RELEASE_wasm")
        } else {
            Issue.record("expected wasm-sdk found, got \(report.wasmSDK)")
        }
    }

    // MARK: divergence #1 — the SDK filter must be the BUILD path's filter

    @Test("doctor picks the same SDK the build path would (hasSuffix _wasm, not contains wasm)")
    func sdkFilterMatchesBuildPath() {
        let runner = healthyRunner(sdkList: ok("my-wasm-toolkit\nswift-6.3.2-RELEASE_wasm\n"))
        let report = DoctorCommand.makeReport(using: runner, macToolchain: nil)
        if case .found(let sdk) = report.wasmSDK {
            #expect(sdk == "swift-6.3.2-RELEASE_wasm",
                    "'my-wasm-toolkit' contains 'wasm' but is not an SDK the build accepts")
        } else {
            Issue.record("expected wasm-sdk found, got \(report.wasmSDK)")
        }
    }

    @Test("an id containing 'wasm' without the _wasm suffix is NOT blessed")
    func containsWasmIsNotEnough() {
        let runner = healthyRunner(sdkList: ok("my-wasm-toolkit\n"))
        let report = DoctorCommand.makeReport(using: runner, macToolchain: nil)
        if case .missing = report.wasmSDK {
            // Correct: the build path would reject this listing too
            // (BuildCommandError.noWasmSDKInstalled), so doctor must not
            // report a green wasm-sdk row.
        } else {
            Issue.record("doctor blessed an SDK the build would reject: \(report.wasmSDK)")
        }
        #expect(report.exitCode == 1)
    }

    // MARK: divergence #2 — swift resolves through the locator

    @Test("swift is located via `which swift` and versioned at the LOCATED path")
    func swiftResolvedViaLocator() {
        let runner = healthyRunner()
        let report = DoctorCommand.makeReport(using: runner, macToolchain: nil)

        if case .found(let line) = report.swift {
            #expect(line.contains("Apple Swift version 6.3.2"))
        } else {
            Issue.record("expected swift found, got \(report.swift)")
        }
        #expect(runner.calls.contains { $0.arguments == ["which", "swift"] },
                "doctor must resolve swift the way build does — via the locator")
        let versionCall = runner.calls.first { $0.arguments == ["--version"] }
        #expect(versionCall?.executable.path == "/toolchains/bin/swift",
                "the version must come from the LOCATED binary, not whatever bare `env swift` resolves to")
    }

    @Test("swift off PATH: swift row missing, SDK row missing, and no sdk probe is attempted")
    func swiftMissing() {
        let runner = healthyRunner(whichSwift: notFound)
        let report = DoctorCommand.makeReport(using: runner, macToolchain: nil)
        if case .missing = report.swift {} else { Issue.record("expected swift missing") }
        if case .missing = report.wasmSDK {} else { Issue.record("expected wasm-sdk missing") }
        #expect(!runner.calls.contains { $0.arguments == ["sdk", "list"] },
                "no swift binary → nothing to list SDKs with")
        #expect(report.exitCode == 1)
    }

    // MARK: doctor's value-add on top of the shared list — version matching

    @Test("a version-mismatched SDK is incompatible with the remove/install remediation")
    func versionMismatchIsIncompatible() {
        let runner = healthyRunner(sdkList: ok("swift-6.3-RELEASE_wasm\n"))
        let report = DoctorCommand.makeReport(using: runner, macToolchain: nil)
        if case .incompatible(let detail, let hint) = report.wasmSDK {
            #expect(detail.contains("6.3"))
            #expect(detail.contains("6.3.2"))
            #expect(hint.contains("swift sdk remove swift-6.3-RELEASE_wasm"))
            #expect(hint.contains("swift sdk install"))
        } else {
            Issue.record("expected incompatible, got \(report.wasmSDK)")
        }
        #expect(report.exitCode == 1)
    }

    @Test("an unparseable compiler version falls back to presence-only SDK acceptance")
    func unparseableVersionFallsBackToPresence() {
        let runner = healthyRunner(versionLine: "some unexpected banner")
        let report = DoctorCommand.makeReport(using: runner, macToolchain: nil)
        if case .found(let sdk) = report.wasmSDK {
            #expect(sdk == "swift-6.3.2-RELEASE_wasm")
        } else {
            Issue.record("presence-only fallback must not flag a mismatch it can't compute, got \(report.wasmSDK)")
        }
    }

    @Test("a failing `swift sdk list` reports the SDK row missing (not a crash)")
    func sdkListFailure() {
        let runner = healthyRunner(sdkList: ProcessResult(exitCode: 2, standardOutput: nil, standardError: "boom"))
        let report = DoctorCommand.makeReport(using: runner, macToolchain: nil)
        if case .missing = report.wasmSDK {} else { Issue.record("expected wasm-sdk missing, got \(report.wasmSDK)") }
        #expect(report.exitCode == 1)
    }

    // MARK: wasm-opt through the runner

    @Test("wasm-opt missing is reported and fails the run")
    func wasmOptMissing() {
        let runner = healthyRunner(wasmOpt: notFound)
        let report = DoctorCommand.makeReport(using: runner, macToolchain: nil)
        if case .missing = report.wasmOpt {} else { Issue.record("expected wasm-opt missing") }
        #expect(report.exitCode == 1)
    }

    @Test("the mac-toolchain row is whatever the caller injects (FS probe, not runner-reachable)")
    func macToolchainInjected() {
        let report = DoctorCommand.makeReport(
            using: healthyRunner(),
            macToolchain: .found("org.swift.632202512111a")
        )
        #expect(report.exitCode == 0)
        #expect(report.summary.contains("org.swift.632202512111a"))
    }
}
