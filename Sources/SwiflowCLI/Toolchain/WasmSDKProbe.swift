// Sources/SwiflowCLI/Toolchain/WasmSDKProbe.swift
//
// Wraps `swift sdk list` and filters its output to WASM SDK IDs. Used by
// BuildCommand to pick the right --swift-sdk argument when the user hasn't
// passed one explicitly.

import Foundation

/// Errors thrown by `WasmSDKProbe.list()`. A non-zero exit from
/// `swift sdk list` is distinct from "list returned no WASM SDKs":
/// the former indicates a broken toolchain (e.g., Swift too old to know
/// the `sdk` subcommand); the latter is a legitimate state callers handle
/// by prompting the user to `swift sdk install`. Carrying stderr lets
/// callers surface the real diagnostic instead of the misleading
/// "no WASM SDK installed".
enum WasmSDKProbeError: Error, Equatable {
    case sdkSubcommandFailed(exitCode: Int32, stderr: String?)
}

struct WasmSDKProbe {
    let runner: ProcessRunner
    let swiftExecutable: URL

    init(runner: ProcessRunner, swiftExecutable: URL) {
        self.runner = runner
        self.swiftExecutable = swiftExecutable
    }

    /// Runs `swift sdk list` and returns the parsed WASM SDK identifiers.
    ///
    /// Throws `WasmSDKProbeError.sdkSubcommandFailed` when the subprocess
    /// exits non-zero. A successful run with no `_wasm` suffix in the
    /// listing returns `[]` (the caller decides what that means).
    func list() throws -> [String] {
        let result = try runner.run(
            executable: swiftExecutable,
            arguments: ["sdk", "list"],
            workingDirectory: nil,
            environment: nil,
            captureOutput: true
        )
        guard result.exitCode == 0 else {
            throw WasmSDKProbeError.sdkSubcommandFailed(
                exitCode: result.exitCode,
                stderr: result.standardError
            )
        }
        let stdout = result.standardOutput ?? ""
        return Self.parseSDKList(stdout)
    }

    /// Filters a `swift sdk list` listing to identifiers ending in `_wasm`.
    /// The suffix convention is what the Swift WASM SDK ships under — both
    /// release SDKs (`swift-6.3-RELEASE_wasm`) and development snapshots
    /// (`swift-DEVELOPMENT-SNAPSHOT-..._wasm`) match.
    static func parseSDKList(_ output: String) -> [String] {
        output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.hasSuffix("_wasm") }
    }

    /// Convenience: parse + pick the first WASM SDK from a `swift sdk list`
    /// output string. Returns nil if none.
    static func pickDefault(from output: String) -> String? {
        parseSDKList(output).first
    }
}
