// Sources/SwiflowCLI/Process/ProcessRunner.swift
//
// Thin Foundation.Process wrapper. The protocol exists so BuildCommand
// can be tested with a StubProcessRunner that records the argv without
// shelling out.

import Foundation

/// Drains one FileHandle to completion on a background queue. `@unchecked
/// Sendable` is sound here: the handle and buffer are touched only inside
/// `drain()`, and the result is read only after `DispatchGroup.wait()`
/// establishes happens-before.
private final class FileHandleDrain: @unchecked Sendable {
    let handle: FileHandle
    var data = Data()
    init(_ handle: FileHandle) { self.handle = handle }
    func drain() { data = handle.readDataToEndOfFile() }
}

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

        // Drain BOTH pipes concurrently before waitUntilExit(). A sequential
        // stdout-then-stderr read deadlocks when the child fills the second
        // pipe's buffer (~64 KiB) while we're still blocked on the first —
        // exactly what a verbose `swift build -v` does. One reader per pipe.
        //
        // Use DEDICATED threads, not the shared libdispatch pool: a `.concurrent`
        // DispatchQueue draws workers from the global pool, and under a saturated
        // pool — e.g. a parallel test runner spawning many processes at once — the
        // two drain blocks can fail to get a worker while this thread is parked in
        // `wait()`, deadlocking on a full pipe buffer. (Foundation's scheduling
        // tightened in Swift 6.3.2 and began hitting this in CI.) A plain Thread
        // always runs regardless of pool pressure and is short-lived (reads to EOF
        // then exits), so it doesn't accumulate.
        let outDrain = outPipe.map { FileHandleDrain($0.fileHandleForReading) }
        let errDrain = errPipe.map { FileHandleDrain($0.fileHandleForReading) }
        let group = DispatchGroup()
        func startDrain(_ drain: FileHandleDrain) {
            group.enter()
            let thread = Thread {
                drain.drain()
                group.leave()
            }
            thread.name = "swiflow.procrunner.drain"
            thread.start()
        }
        if let outDrain { startDrain(outDrain) }
        if let errDrain { startDrain(errDrain) }
        group.wait()
        process.waitUntilExit()

        let stdout = outDrain.flatMap { String(data: $0.data, encoding: .utf8) }
        let stderr = errDrain.flatMap { String(data: $0.data, encoding: .utf8) }

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
