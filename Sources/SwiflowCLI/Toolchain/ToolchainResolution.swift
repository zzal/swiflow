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
// Throws the typed `SwiflowRuntimeError` directly at each of the three
// toolchain failure sites (`.toolchain` category — each carries the doctor
// pointer). ArgumentParser prints these cleanly, no usage help. Other errors
// (e.g. a Process launch failure from SwiftExecutableLocator or WasmSDKProbe)
// propagate unmodified.

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
            throw SwiflowRuntimeError.swiftNotOnPath
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
                throw SwiflowRuntimeError.wasmSDKListFailed(exitCode: exitCode, stderr: stderr)
            }
            guard let firstInstalled = installed.first else {
                throw SwiflowRuntimeError.noWasmSDKInstalled
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
