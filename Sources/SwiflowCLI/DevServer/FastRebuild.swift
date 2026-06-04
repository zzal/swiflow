// Sources/SwiflowCLI/DevServer/FastRebuild.swift
//
// Dev-only fast rebuild: produce a fresh wasm with a plain `swift build`
// and copy it over the served PackageToJS output, skipping the full
// `swift package js` packaging pipeline (which reruns all 14 MiniMake tasks
// every save — ~17s of waste). The JS glue is invariant across edits
// (Swiflow apps have an empty wasm-imports set), so reusing it is safe.
// See docs/superpowers/specs/2026-06-04-fast-dev-rebuild-loop-design.md.

import Foundation

/// Composes + runs `swift build --swift-sdk <id> --product App` — a plain
/// debug wasm build, NOT the `swift package js` plugin. Mirrors
/// `BuildInvocation`'s shape (argv composer + ProcessRunner.run) so the argv
/// is unit-testable without spawning a process.
struct RawWasmBuildInvocation {
    let swiftExecutable: URL
    let projectPath: URL
    let swiftSDK: String
    let toolchainBundleID: String?

    func composeArguments() -> [String] {
        ["build", "--swift-sdk", swiftSDK, "--product", "App"]
    }

    /// Runs the build, inheriting stdout/stderr (so the user sees progress).
    /// Throws `BuildCommandError.swiftBuildFailed` on a non-zero exit.
    @discardableResult
    func run(using runner: ProcessRunner) throws -> ProcessResult {
        let environment: [String: String]? = toolchainBundleID.map { ["TOOLCHAINS": $0] }
        let result = try runner.run(
            executable: swiftExecutable,
            arguments: composeArguments(),
            workingDirectory: projectPath,
            environment: environment,
            captureOutput: false
        )
        if result.exitCode != 0 {
            throw BuildCommandError.swiftBuildFailed(exitCode: result.exitCode)
        }
        return result
    }
}
