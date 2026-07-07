// Tests/SwiflowCLITests/Process/DiagnosticsRecordingRunnerTests.swift
//
// Audit III Wave-2 #7 — the dev rebuild loop's runner wrapper. The rebuild
// invocations run with captureOutput:false (streams inherited) so compiler
// diagnostics were gone by the time the loop's catch wanted to forward them
// to the browser; worse, the capture-path rebuild (CapturingWasmBuild-
// Invocation) captured diagnostics and DISCARDED them on throw, so a
// mid-edit compile error during a recapture showed nothing but "exit code
// 1" anywhere. The wrapper always captures from the child, echoes what
// streaming callers expected (post-exit), echoes capture-callers' output on
// failure (closing that hole), and records the last failing run's combined
// output for the browser overlay.
import Foundation
import Testing
@testable import SwiflowCLI

/// Base stub that records the captureOutput flag (StubProcessRunner's Call
/// doesn't) and returns a queue of results.
private final class CaptureFlagRecordingStub: ProcessRunner {
    private(set) var captureFlags: [Bool] = []
    var results: [ProcessResult]

    init(results: [ProcessResult]) {
        self.results = results
    }

    func run(
        executable: URL,
        arguments: [String],
        workingDirectory: URL?,
        environment: [String: String]?,
        captureOutput: Bool
    ) throws -> ProcessResult {
        captureFlags.append(captureOutput)
        return results.isEmpty ? ProcessResult(exitCode: 0, standardOutput: nil, standardError: nil) : results.removeFirst()
    }
}

@Suite("DiagnosticsRecordingRunner")
struct DiagnosticsRecordingRunnerTests {

    private func ok(_ out: String? = nil, _ err: String? = nil) -> ProcessResult {
        ProcessResult(exitCode: 0, standardOutput: out, standardError: err)
    }
    private func failed(_ out: String? = nil, _ err: String? = nil) -> ProcessResult {
        ProcessResult(exitCode: 1, standardOutput: out, standardError: err)
    }
    private func run(_ runner: DiagnosticsRecordingRunner, captureOutput: Bool) throws -> ProcessResult {
        try runner.run(
            executable: URL(fileURLWithPath: "/usr/bin/swift"),
            arguments: ["build"],
            workingDirectory: nil,
            environment: nil,
            captureOutput: captureOutput
        )
    }

    @Test("always captures from the child, whatever the caller asked for")
    func alwaysCaptures() throws {
        let base = CaptureFlagRecordingStub(results: [ok(), ok()])
        let runner = DiagnosticsRecordingRunner(base: base, echo: { _ in })
        _ = try run(runner, captureOutput: false)
        _ = try run(runner, captureOutput: true)
        #expect(base.captureFlags == [true, true])
    }

    @Test("a failing run records its combined stdout+stderr")
    func recordsFailureOutput() throws {
        let base = CaptureFlagRecordingStub(results: [failed("out-line\n", "error: no\n")])
        let runner = DiagnosticsRecordingRunner(base: base, echo: { _ in })
        _ = try run(runner, captureOutput: false)
        let recorded = try #require(runner.lastFailureOutput)
        #expect(recorded.contains("out-line"))
        #expect(recorded.contains("error: no"))
    }

    @Test("successful runs record nothing; reset() clears a prior failure")
    func successAndReset() throws {
        let base = CaptureFlagRecordingStub(results: [ok("fine\n"), failed(nil, "boom\n")])
        let runner = DiagnosticsRecordingRunner(base: base, echo: { _ in })
        _ = try run(runner, captureOutput: false)
        #expect(runner.lastFailureOutput == nil)
        _ = try run(runner, captureOutput: false)
        #expect(runner.lastFailureOutput != nil)
        runner.reset()
        #expect(runner.lastFailureOutput == nil)
    }

    @Test("capture-requesting callers still get the output in the result")
    func capturePassthrough() throws {
        let base = CaptureFlagRecordingStub(results: [ok("verbose swiftc lines\n")])
        let runner = DiagnosticsRecordingRunner(base: base, echo: { _ in })
        let result = try run(runner, captureOutput: true)
        #expect(result.standardOutput == "verbose swiftc lines\n")
    }

    @Test("streaming callers get their output echoed post-exit")
    func echoesForStreamingCallers() throws {
        let base = CaptureFlagRecordingStub(results: [ok("progress\n", "warnings\n")])
        var echoed: [String] = []
        let runner = DiagnosticsRecordingRunner(base: base, echo: { echoed.append($0) })
        _ = try run(runner, captureOutput: false)
        #expect(echoed.joined().contains("progress"))
        #expect(echoed.joined().contains("warnings"))
    }

    @Test("capture-requesting callers are echoed ONLY on failure (closes the discarded-diagnostics hole)")
    func echoesCaptureCallersOnFailureOnly() throws {
        let base = CaptureFlagRecordingStub(results: [ok("quiet\n"), failed(nil, "error: bad\n")])
        var echoed: [String] = []
        let runner = DiagnosticsRecordingRunner(base: base, echo: { echoed.append($0) })
        _ = try run(runner, captureOutput: true)
        #expect(echoed.isEmpty, "successful capture runs stay quiet — their caller consumes the output")
        _ = try run(runner, captureOutput: true)
        #expect(echoed.joined().contains("error: bad"),
                "a failed capture run must surface its diagnostics on the terminal")
    }
}
