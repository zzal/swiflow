// Sources/SwiflowCLI/Toolchain/ToolchainResolution.swift
//
// `swiflow build` and `swiflow dev` both need to locate `swift` on PATH,
// resolve the WASM SDK identifier (user override or the first entry from
// `swift sdk list`), and detect a TOOLCHAINS bundle ID on macOS when the
// env var isn't already pinned. That ~30-line sequence — including the
// exact error translation — used to be duplicated in both commands and
// had already drifted once. This is the single source of truth both
// commands now call.
//
// Throws `ValidationError` directly at each of the three failure sites,
// matching the two commands' original inline `throw ValidationError(...)`
// call sites exactly — callers don't need a translation step. Other
// errors (e.g. a Process launch failure from SwiftExecutableLocator or
// WasmSDKProbe) propagate unmodified, same as before extraction.

import ArgumentParser
import Foundation

enum ToolchainResolution {
    struct Result: Sendable {
        let swift: URL
        let sdk: String
        let toolchainBundleID: String?
    }

    static func resolve(swiftSDKOverride: String?, using runner: ProcessRunner) throws -> Result {
        guard let swift = try SwiftExecutableLocator.locate(using: runner) else {
            throw ValidationError(String(describing: BuildCommandError.swiftNotOnPath))
        }

        let sdk: String
        if let userSDK = swiftSDKOverride {
            sdk = userSDK
        } else {
            let probe = WasmSDKProbe(runner: runner, swiftExecutable: swift)
            let installed: [String]
            do {
                installed = try probe.list()
            } catch let WasmSDKProbeError.sdkSubcommandFailed(exitCode, stderr) {
                throw ValidationError(String(describing: BuildCommandError.wasmSDKListFailed(
                    exitCode: exitCode,
                    stderr: stderr
                )))
            }
            guard let firstInstalled = installed.first else {
                throw ValidationError(String(describing: BuildCommandError.noWasmSDKInstalled))
            }
            sdk = firstInstalled
        }

        // Respect the user's own TOOLCHAINS pin; only auto-detect when unset.
        let toolchainBundleID: String? = ProcessInfo.processInfo.environment["TOOLCHAINS"] != nil
            ? nil
            : MacToolchainProbe.swiftLatestBundleIdentifier()

        return Result(swift: swift, sdk: sdk, toolchainBundleID: toolchainBundleID)
    }
}
