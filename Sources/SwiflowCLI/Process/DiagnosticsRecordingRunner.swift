// Sources/SwiflowCLI/Process/DiagnosticsRecordingRunner.swift
//
// The dev rebuild loop's runner wrapper (audit III Wave-2 #7). The rebuild
// invocations ask for captureOutput:false (inherited streams), so compiler
// diagnostics were gone by the time the loop's catch wanted to forward them
// to the browser overlay — and the capture-path rebuild
// (CapturingWasmBuildInvocation) captured its diagnostics and DISCARDED
// them on throw, so a mid-edit compile error during a recapture showed
// nothing but "exit code 1" anywhere at all.
//
// The wrapper always captures from the child and then routes:
//   - streaming callers (captureOutput:false) get their output echoed
//     post-exit — the terminal still sees everything, just not live. For
//     the ~1.6s bypass replay that's indistinguishable; the rare in-loop
//     full-build fallback loses live progress, an accepted trade for
//     diagnostics reaching the browser.
//   - capture callers get their result untouched, and are echoed ONLY on
//     failure — closing the discarded-diagnostics hole above.
//   - any failing run's combined output is recorded in lastFailureOutput
//     for the loop's catch to forward. reset() at the top of each rebuild
//     keeps a stale failure from leaking into the next save's report.
//
// Deliberately NOT applied to the initial build (no browser is connected
// yet, and live progress matters most there).

import Foundation

final class DiagnosticsRecordingRunner: ProcessRunner {
    private let base: ProcessRunner
    private let echo: (String) -> Void

    /// Combined stdout+stderr of the most recent non-zero-exit run.
    private(set) var lastFailureOutput: String?

    init(base: ProcessRunner, echo: ((String) -> Void)? = nil) {
        self.base = base
        self.echo = echo ?? { chunk in
            // stdout keeps line-buffered ordering with the loop's own prints.
            print(chunk, terminator: "")
        }
    }

    func reset() {
        lastFailureOutput = nil
    }

    func run(
        executable: URL,
        arguments: [String],
        workingDirectory: URL?,
        environment: [String: String]?,
        captureOutput: Bool
    ) throws -> ProcessResult {
        let result = try base.run(
            executable: executable,
            arguments: arguments,
            workingDirectory: workingDirectory,
            environment: environment,
            captureOutput: true
        )

        let combined = [result.standardOutput, result.standardError]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        let failed = result.exitCode != 0
        if failed {
            lastFailureOutput = combined
        }
        // Streaming callers expected to see everything; capture callers
        // consume their output themselves — except on failure, where they
        // historically threw it away.
        if !captureOutput || failed {
            if !combined.isEmpty { echo(combined + "\n") }
        }
        return result
    }
}
