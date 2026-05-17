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
        process.waitUntilExit()

        let stdout = outPipe.flatMap { pipe -> String? in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        }
        let stderr = errPipe.flatMap { pipe -> String? in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        }

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
