// Sources/SwiflowCLI/Process/SwiftExecutableLocator.swift
//
// Resolves the path to the `swift` binary BuildCommand should invoke.
// We look it up via `/usr/bin/env which swift` so the child process honors
// the user's PATH — this matches the behavior of running `swift` directly
// in the user's shell and avoids hard-coding an install location that
// varies by platform (Homebrew, Xcode, Swiftly, swift-actions, distro
// packages).

import Foundation

enum SwiftExecutableLocator {
    /// Looks up `swift` on PATH via `which swift`. Returns the absolute
    /// path the parent's PATH resolves `swift` to, or nil if `swift` isn't
    /// on PATH.
    static func locate(using runner: ProcessRunner) throws -> URL? {
        let result = try runner.run(
            executable: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["which", "swift"],
            workingDirectory: nil,
            environment: nil,
            captureOutput: true
        )
        guard result.exitCode == 0, let stdout = result.standardOutput else {
            return nil
        }
        // `which` typically prints one line, but on a misconfigured PATH or with
        // wrapping aliases it can print multiple. Take the first non-empty line.
        let firstLine = stdout
            .split(separator: "\n")
            .first
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard let path = firstLine, !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }
}
