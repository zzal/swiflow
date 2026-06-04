import Foundation
import Testing
@testable import SwiflowCLI

@Suite("SystemProcessRunner concurrent drain")
struct ProcessRunnerDrainTests {

    // A child that interleaves >64 KiB to BOTH stdout and stderr. With a
    // sequential stdout-then-stderr drain this deadlocks; with concurrent
    // drain it completes. ~6000 lines × ~20 bytes ≫ the 64 KiB pipe buffer.
    @Test("Captures large output on both streams without deadlocking", .timeLimit(.minutes(1)))
    func drainsBothStreams() throws {
        let runner = SystemProcessRunner()
        let script = "i=0; while [ $i -lt 6000 ]; do echo out-line-$i; echo err-line-$i 1>&2; i=$((i+1)); done"
        let result = try runner.run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script],
            workingDirectory: nil,
            environment: nil,
            captureOutput: true
        )
        #expect(result.exitCode == 0)
        let out = try #require(result.standardOutput)
        let err = try #require(result.standardError)
        #expect(out.contains("out-line-0"))
        #expect(out.contains("out-line-5999"))
        #expect(err.contains("err-line-0"))
        #expect(err.contains("err-line-5999"))
    }
}
