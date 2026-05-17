// Sources/SwiflowCLI/Toolchain/WasmSDKProbe.swift
//
// Wraps `swift sdk list` and filters its output to WASM SDK IDs. Used by
// BuildCommand to pick the right --swift-sdk argument when the user hasn't
// passed one explicitly.

import Foundation

struct WasmSDKProbe {
    let runner: ProcessRunner
    let swiftExecutable: URL

    init(runner: ProcessRunner, swiftExecutable: URL) {
        self.runner = runner
        self.swiftExecutable = swiftExecutable
    }

    /// Runs `swift sdk list` and returns the parsed WASM SDK identifiers.
    func list() throws -> [String] {
        let result = try runner.run(
            executable: swiftExecutable,
            arguments: ["sdk", "list"],
            workingDirectory: nil,
            environment: nil,
            captureOutput: true
        )
        guard result.exitCode == 0, let stdout = result.standardOutput else {
            return []
        }
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
