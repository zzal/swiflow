// Tests/SwiflowCLITests/ProcessRunnerTests.swift
import Foundation
import Testing
@testable import SwiflowCLI

@Suite("ProcessRunner")
struct ProcessRunnerTests {

    @Test("SystemProcessRunner runs /bin/echo and returns exit code 0 + captured stdout")
    func runsEcho() throws {
        let runner = SystemProcessRunner()
        let result = try runner.run(
            executable: URL(fileURLWithPath: "/bin/echo"),
            arguments: ["hello", "world"],
            workingDirectory: nil,
            environment: nil,
            captureOutput: true
        )
        #expect(result.exitCode == 0)
        #expect(result.standardOutput?.trimmingCharacters(in: .whitespacesAndNewlines) == "hello world")
    }

    @Test("SystemProcessRunner propagates non-zero exit codes")
    func nonZeroExitCode() throws {
        let runner = SystemProcessRunner()
        let result = try runner.run(
            executable: URL(fileURLWithPath: "/usr/bin/false"),
            arguments: [],
            workingDirectory: nil,
            environment: nil,
            captureOutput: false
        )
        #expect(result.exitCode == 1)
    }

    @Test("StubProcessRunner records arguments without executing")
    func stubRecords() throws {
        let stub = StubProcessRunner(stubbedExitCode: 0)
        _ = try stub.run(
            executable: URL(fileURLWithPath: "/usr/bin/swift"),
            arguments: ["package", "js"],
            workingDirectory: URL(fileURLWithPath: "/tmp/proj"),
            environment: ["FOO": "BAR"],
            captureOutput: false
        )
        #expect(stub.calls.count == 1)
        #expect(stub.calls[0].arguments == ["package", "js"])
        #expect(stub.calls[0].workingDirectory?.path == "/tmp/proj")
        #expect(stub.calls[0].environment?["FOO"] == "BAR")
    }
}
