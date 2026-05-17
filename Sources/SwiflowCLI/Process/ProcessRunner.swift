// Sources/SwiflowCLI/Process/ProcessRunner.swift
//
// Thin Foundation.Process wrapper. The protocol exists so BuildCommand
// can be tested with a StubProcessRunner that records the argv without
// shelling out.

import Foundation

struct ProcessResult: Equatable {
    let exitCode: Int32
    /// Captured stdout, only populated when `captureOutput == true`. nil otherwise.
    let standardOutput: String?
    /// Captured stderr, only populated when `captureOutput == true`. nil otherwise.
    let standardError: String?
}

// MARK: - Protocol
//
// ProcessRunner is NOT `Sendable`. SystemProcessRunner is stateless but
// final-class identity matters for shared use; StubProcessRunner records
// calls in mutable state. Hold one instance per call site / actor and do
// not capture into `Task { }` closures crossing actor boundaries. If a
// future caller needs to share across actors, mark the protocol Sendable
// and gate StubProcessRunner.calls with a lock.
protocol ProcessRunner: AnyObject {
    func run(
        executable: URL,
        arguments: [String],
        workingDirectory: URL?,
        environment: [String: String]?,
        captureOutput: Bool
    ) throws -> ProcessResult
}

final class SystemProcessRunner: ProcessRunner {
    init() {}

    func run(
        executable: URL,
        arguments: [String],
        workingDirectory: URL?,
        environment: [String: String]?,
        captureOutput: Bool
    ) throws -> ProcessResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let workingDirectory = workingDirectory {
            process.currentDirectoryURL = workingDirectory
        }
        if let environment = environment {
            // Merge with the parent's environment so PATH and friends survive,
            // letting the caller override or extend specific keys.
            var merged = ProcessInfo.processInfo.environment
            for (key, value) in environment {
                merged[key] = value
            }
            process.environment = merged
        }

        let outPipe: Pipe?
        let errPipe: Pipe?
        if captureOutput {
            let o = Pipe()
            let e = Pipe()
            process.standardOutput = o
            process.standardError = e
            outPipe = o
            errPipe = e
        } else {
            // Inherit parent's streams so the user sees swift's progress.
            outPipe = nil
            errPipe = nil
        }

        try process.run()

        // Drain pipes BEFORE waitUntilExit() to avoid deadlock: if the child
        // writes more than the OS pipe buffer (~16-64 KiB on Darwin) without
        // a reader, it will block on write() while we block on waitUntilExit().
        // readDataToEndOfFile() blocks until the writer closes its end (on
        // child exit), so it implicitly waits for the child to finish AND
        // drains the pipe at the same time.
        //
        // Limitation: this reads stdout then stderr sequentially. A child
        // that writes >64 KiB to BOTH streams could still block on the
        // stderr write while we're still reading stdout. The fully-correct
        // fix uses concurrent reads (one queue per pipe). The current call
        // sites (T7 captures small `swift sdk list` output; T9 uses
        // captureOutput: false for big build logs) don't hit this case.
        let outData: Data? = outPipe?.fileHandleForReading.readDataToEndOfFile()
        let errData: Data? = errPipe?.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let stdout = outData.flatMap { String(data: $0, encoding: .utf8) }
        let stderr = errData.flatMap { String(data: $0, encoding: .utf8) }

        return ProcessResult(
            exitCode: process.terminationStatus,
            standardOutput: stdout,
            standardError: stderr
        )
    }
}

// MARK: - Test stub

/// Records calls without executing. Returns whatever `stubbedExitCode` /
/// `stubbedStandardOutput` were configured with.
final class StubProcessRunner: ProcessRunner {
    struct Call: Equatable {
        let executable: URL
        let arguments: [String]
        let workingDirectory: URL?
        let environment: [String: String]?
    }

    var stubbedExitCode: Int32
    var stubbedStandardOutput: String?
    var stubbedStandardError: String?
    private(set) var calls: [Call] = []

    init(stubbedExitCode: Int32 = 0, stubbedStandardOutput: String? = nil, stubbedStandardError: String? = nil) {
        self.stubbedExitCode = stubbedExitCode
        self.stubbedStandardOutput = stubbedStandardOutput
        self.stubbedStandardError = stubbedStandardError
    }

    func run(
        executable: URL,
        arguments: [String],
        workingDirectory: URL?,
        environment: [String: String]?,
        captureOutput: Bool
    ) throws -> ProcessResult {
        calls.append(Call(
            executable: executable,
            arguments: arguments,
            workingDirectory: workingDirectory,
            environment: environment
        ))
        return ProcessResult(
            exitCode: stubbedExitCode,
            standardOutput: stubbedStandardOutput,
            standardError: stubbedStandardError
        )
    }
}
