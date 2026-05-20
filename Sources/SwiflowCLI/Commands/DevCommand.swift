// Sources/SwiflowCLI/Commands/DevCommand.swift
//
// `swiflow dev` — initial dev build, then start the dev server, then
// start the file watcher and rebuild + broadcast reload on every save.
//
// The command never returns under normal operation; it blocks on
// server.run() and is shut down via SIGINT/SIGTERM. The file-watcher
// pump is a background Task that the outer cancellation tears down.

import ArgumentParser
import Foundation

struct DevCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dev",
        abstract: "Start the Swiflow dev server with file-watch + browser reload."
    )

    @Option(
        name: .customLong("path"),
        help: "Path to the Swiflow project directory. Defaults to the current working directory."
    )
    var path: String = "."

    @Option(
        name: .customLong("port"),
        help: "HTTP port for the dev server. Default 3000."
    )
    var port: Int = 3000

    @Option(
        name: .customLong("swift-sdk"),
        help: "Override the Swift WASM SDK identifier."
    )
    var swiftSDK: String?

    func run() async throws {
        let runner = SystemProcessRunner()

        // 0. Validate the project path.
        let projectURL = URL(fileURLWithPath: path).standardizedFileURL
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: projectURL.path, isDirectory: &isDir), isDir.boolValue else {
            throw ValidationError(String(describing: BuildCommandError.projectPathNotFound(projectURL)))
        }

        // 1. Locate swift on PATH.
        guard let swift = try SwiftExecutableLocator.locate(using: runner) else {
            throw ValidationError(String(describing: BuildCommandError.swiftNotOnPath))
        }

        // 2. Resolve the WASM SDK.
        let sdk: String
        if let userSDK = swiftSDK {
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

        // 3. Toolchain on macOS.
        let toolchainBundleID: String? = ProcessInfo.processInfo.environment["TOOLCHAINS"] != nil
            ? nil
            : MacToolchainProbe.swiftLatestBundleIdentifier()

        // 4. Initial build. Failures here exit non-zero (Phase 2c
        //    decision §6 — nothing to serve if the first build fails).
        let invocation = BuildInvocation(
            swiftExecutable: swift,
            projectPath: projectURL,
            swiftSDK: sdk,
            toolchainBundleID: toolchainBundleID,
            configuration: .dev
        )
        print("swiflow: initial build (dev configuration)...")
        do {
            _ = try invocation.run(using: runner)
        } catch let error as BuildCommandError {
            throw ValidationError(String(describing: error))
        }

        // 5. Start the dev server.
        let server = DevServer(projectRoot: projectURL, port: port)
        print("swiflow: dev server listening on http://localhost:\(port)")

        // 6. Start the file watcher in a background task. On each
        //    change, rebuild and broadcast reload (decision §2: don't
        //    broadcast on failed rebuilds).
        let watcher = FileWatcher(
            root: projectURL,
            interval: .milliseconds(250),
            extensions: ["swift", "html", "js"]
        )

        // Run the server and the watcher pump concurrently. Either
        // exiting tears down the other.
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await server.run()
            }
            group.addTask {
                // ProcessRunner is intentionally non-Sendable (see
                // ProcessRunner.swift §"Hold one instance per call site").
                // The outer `runner` belongs to the parent task; this
                // task gets its own stateless SystemProcessRunner for
                // the rebuild loop.
                let rebuildRunner = SystemProcessRunner()
                for await changed in watcher.changes() {
                    print("swiflow: rebuilding (\(changed.count) file\(changed.count == 1 ? "" : "s") changed)...")
                    do {
                        _ = try invocation.run(using: rebuildRunner)
                        let bust = Self.wasmCacheBusterSuffix(projectURL: projectURL)
                        await server.hub.broadcastHMRSwap(
                            wasmURL: "/\(Self.packageToJSOutputRelativePath)/App.wasm?h=\(bust)",
                            jsURL: "/\(Self.packageToJSOutputRelativePath)/index.js?h=\(bust)"
                        )
                        print("swiflow: HMR broadcast")
                    } catch {
                        print("swiflow: rebuild failed — \(error). Browser unchanged; fix and save to retry.")
                    }
                }
            }
            try await group.next()
            group.cancelAll()
        }
    }

    /// PackageToJS plugin output directory, relative to the project
    /// root. Mirrors the path the `swift package js` plugin writes to;
    /// kept in one place so the cache-buster URL composition and the
    /// mtime stat both use the same source of truth.
    static let packageToJSOutputRelativePath = ".build/plugins/PackageToJS/outputs/Package"

    /// Returns a cache-busting suffix derived from the mtime of the
    /// built `App.wasm` in milliseconds. Falls back to a `Date()`-based
    /// suffix when the file can't be stat'd (e.g. very first dev-loop
    /// rebuild raced ahead of the FS flush). The exact suffix doesn't
    /// matter as long as it changes between rebuilds — the browser
    /// just needs a URL that bypasses any cached response from a
    /// previous build.
    static func wasmCacheBusterSuffix(projectURL: URL) -> String {
        let wasmPath = projectURL
            .appendingPathComponent(packageToJSOutputRelativePath)
            .appendingPathComponent("App.wasm")
        if let attrs = try? FileManager.default.attributesOfItem(atPath: wasmPath.path),
           let mtime = attrs[.modificationDate] as? Date {
            return String(Int(mtime.timeIntervalSince1970 * 1000))
        }
        return String(Int(Date().timeIntervalSince1970 * 1000))
    }
}
