// Sources/SwiflowCLI/DevServer/FastRebuild.swift
//
// Wasm artifact helpers shared by the dev-loop compiler bypass
// (CompilerBypass.swift): locate the raw `swift build` wasm output and copy it
// over the served PackageToJS file, skipping the full `swift package js`
// packaging pipeline (which reruns all 14 MiniMake tasks every save). The JS
// glue is invariant across edits (Swiflow apps have an empty wasm-imports set),
// so reusing it is safe.
// See docs/superpowers/specs/2026-06-04-fast-dev-rebuild-loop-design.md.

import Foundation

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
    /// the caller falls back to the full `swift package js` path. Runs under
    /// the same invocation preamble as the builds whose bin path it predicts
    /// (`SwiftContext`) — a drift here would resolve the artifact under a
    /// different toolchain than the one that builds it.
    static func resolve(context: SwiftContext, using runner: ProcessRunner) -> URL? {
        guard
            let result = try? context.run(
                ["build", "--show-bin-path", "--swift-sdk", context.sdk],
                using: runner,
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
