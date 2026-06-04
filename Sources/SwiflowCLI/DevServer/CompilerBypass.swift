// Sources/SwiflowCLI/DevServer/CompilerBypass.swift
//
// Dev-only "compiler bypass" (Lever 2): on each save, replay SwiftPM's own
// swiftc + wasm-ld commands directly, skipping the ~9s SwiftPM orchestration
// overhead that `swift build` pays on every invocation. Commands are captured
// once from a verbose build and re-captured when the app's source/import set
// or the package manifest changes. See
// docs/superpowers/specs/2026-06-04-compiler-bypass-dev-loop-design.md.

import Foundation

/// One replayable command: an executable plus its full argv.
struct ResolvedCommand: Sendable, Equatable {
    let executable: URL
    let arguments: [String]
}

/// `swift build --swift-sdk <id> --product App -v` with output captured so the
/// emitted swiftc/wasm-ld lines can be parsed. Sibling of `RawWasmBuildInvocation`;
/// the name signals intent (capturing the commands is the purpose, `-v` the means).
struct CapturingWasmBuildInvocation: Sendable {
    let swiftExecutable: URL
    let projectPath: URL
    let swiftSDK: String
    let toolchainBundleID: String?

    func composeArguments() -> [String] {
        ["build", "--swift-sdk", swiftSDK, "--product", "App", "-v"]
    }

    /// Runs the build (which also produces the wasm) and returns the combined
    /// stdout+stderr — SwiftPM's verbose command lines can appear on either
    /// stream, and the version may vary, so we hand the parser both.
    func run(using runner: ProcessRunner) throws -> String {
        let environment: [String: String]? = toolchainBundleID.map { ["TOOLCHAINS": $0] }
        let result = try runner.run(
            executable: swiftExecutable,
            arguments: composeArguments(),
            workingDirectory: projectPath,
            environment: environment,
            captureOutput: true
        )
        if result.exitCode != 0 {
            throw BuildCommandError.swiftBuildFailed(exitCode: result.exitCode)
        }
        return (result.standardOutput ?? "") + "\n" + (result.standardError ?? "")
    }
}
