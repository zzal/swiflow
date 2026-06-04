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
struct RawWasmBuildInvocation: Sendable {
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

/// Resolves the raw `swift build` wasm artifact path. The build triple
/// (e.g. `wasm32-unknown-wasip1`) varies by SDK, so we query SwiftPM for the
/// bin directory rather than hardcoding it. `--show-bin-path` is a query: it
/// evaluates the manifest (~1s) but does not build, so it's cheap to run once
/// at dev startup.
enum WasmArtifactLocator {
    /// Parse `--show-bin-path` stdout into the bin directory path. The path is
    /// the only real output; we take the last non-empty trimmed line to be
    /// robust against a stray warning printed before it.
    static func parseBinPath(_ stdout: String) -> String? {
        stdout
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .last { !$0.isEmpty }
    }

    /// Query the bin path and append `App.wasm`. Returns nil on any failure —
    /// the caller falls back to the full `swift package js` path.
    static func resolve(
        swiftExecutable: URL,
        projectPath: URL,
        swiftSDK: String,
        toolchainBundleID: String?,
        using runner: ProcessRunner
    ) -> URL? {
        let environment: [String: String]? = toolchainBundleID.map { ["TOOLCHAINS": $0] }
        guard
            let result = try? runner.run(
                executable: swiftExecutable,
                arguments: ["build", "--show-bin-path", "--swift-sdk", swiftSDK],
                workingDirectory: projectPath,
                environment: environment,
                captureOutput: true
            ),
            result.exitCode == 0,
            let stdout = result.standardOutput,
            let binPath = parseBinPath(stdout)
        else {
            return nil
        }
        return URL(fileURLWithPath: binPath).appendingPathComponent("App.wasm")
    }
}

/// Atomically replaces the served wasm with a freshly-built one. Atomic write
/// avoids serving a half-written file if the dev server reads mid-copy.
enum WasmArtifactCopier {
    static func copy(from source: URL, to dest: URL) throws {
        let data = try Data(contentsOf: source)
        try data.write(to: dest, options: .atomic)
    }
}

/// Coordinates one fast rebuild: build the wasm, then copy it over the served
/// output. Holds the resolved paths so the dev loop just calls `rebuild`.
struct FastRebuilder: Sendable {
    let build: RawWasmBuildInvocation
    /// Raw `swift build` output, e.g. `.build/wasm32-unknown-wasip1/debug/App.wasm`.
    let artifactURL: URL
    /// Served bundle wasm: `.build/plugins/PackageToJS/outputs/Package/App.wasm`.
    let outputWasmURL: URL

    /// Builds (throws `swiftBuildFailed` on a compile error — the caller then
    /// skips the HMR broadcast, leaving the last good bundle in place), then
    /// copies the fresh wasm into the served output.
    func rebuild(using runner: ProcessRunner) throws {
        try build.run(using: runner)
        try WasmArtifactCopier.copy(from: artifactURL, to: outputWasmURL)
    }
}
