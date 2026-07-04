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

    @Flag(
        name: .customLong("experimental-compile-cache"),
        help: ArgumentHelp(
            "Experimental: share a module cache across projects to speed cold builds.",
            visibility: .hidden
        )
    )
    var experimentalCompileCache: Bool = false

    func run() async throws {
        let runner = SystemProcessRunner()

        // 0. Validate the project path.
        let projectURL = URL(fileURLWithPath: path).standardizedFileURL
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: projectURL.path, isDirectory: &isDir), isDir.boolValue else {
            throw ValidationError(String(describing: BuildCommandError.projectPathNotFound(projectURL)))
        }

        // 0.1 Fail fast on a port that's already bound (EADDRINUSE is the most
        //     common first-run failure) instead of letting it surface as a raw
        //     NIO bind error only after paying for the initial build below.
        do {
            try PortAvailability.checkAvailable(port: port)
        } catch let error as PortAvailability.ProbeError {
            throw ValidationError(String(describing: error))
        }

        // 0.5 Ensure the embedded JS driver + service worker are on disk before
        //     the server starts serving. Without this, a project that wasn't
        //     `swiflow init`-ed (or whose gitignored driver was never committed)
        //     serves a 404 on swiflow-driver.js and boots a blank page. Written
        //     once here, before the FileWatcher is created, so it doesn't trip
        //     the rebuild loop.
        do {
            try DriverInstaller.install(into: projectURL, minified: false)
        } catch {
            throw ValidationError("swiflow: failed to write the JS driver into \(projectURL.path): \(error)")
        }

        // 0.6 Remove a leftover `swiflow build` manifest. The manifest is a
        //     build-only artifact; if the service worker finds one here it
        //     precaches the *build* outputs and serves them cache-first,
        //     shadowing every dev rebuild (stale page that survives server
        //     restarts). HTTPRouter also refuses to serve the path, which
        //     covers a manifest recreated mid-session by a concurrent
        //     `swiflow build`.
        try? FileManager.default.removeItem(
            at: projectURL.appendingPathComponent("swiflow-manifest.json"))

        // 1-3. Locate swift, resolve the WASM SDK, and detect TOOLCHAINS —
        //      shared with `swiflow build` (see ToolchainResolution).
        let resolution = try ToolchainResolution.resolve(swiftSDKOverride: swiftSDK, using: runner)
        let swift = resolution.swift
        let sdk = resolution.sdk
        let toolchainBundleID = resolution.toolchainBundleID

        // 3.5 Experimental opt-in: resolve a shared module-cache directory. Wired
        //     into the initial build + the per-save full-build fallback; the fast
        //     bypass rebuilder replays its own captured commands and is already
        //     near-instant, so it doesn't need it.
        let compileCacheDir = CompileCache.resolveAndPrepare(
            flagEnabled: experimentalCompileCache,
            environment: ProcessInfo.processInfo.environment
        )

        // 4. Initial build. Failures here exit non-zero (Phase 2c
        //    decision §6 — nothing to serve if the first build fails).
        let invocation = BuildInvocation(
            swiftExecutable: swift,
            projectPath: projectURL,
            swiftSDK: sdk,
            toolchainBundleID: toolchainBundleID,
            configuration: .dev,
            compileCacheDir: compileCacheDir
        )
        print("swiflow: initial build (dev configuration)...")
        do {
            _ = try invocation.run(using: runner)
        } catch let error as BuildCommandError {
            throw ValidationError(String(describing: error))
        }

        // 4.5 Build the bypass rebuilder. The dev loop replays SwiftPM's own
        //     swiftc + wasm-ld commands per save (~1.6s), re-capturing them via
        //     a full `swift build` whenever the app source/import set or the
        //     manifest changes. If the wasm bin path can't be resolved we leave
        //     it nil and fall back to the full `swift package js` per save.
        let outputWasmURL = projectURL
            .appendingPathComponent(Self.packageToJSOutputRelativePath)
            .appendingPathComponent("App.wasm")
        let bypassRebuilder: BypassRebuilder? = WasmArtifactLocator.resolve(
            swiftExecutable: swift,
            projectPath: projectURL,
            swiftSDK: sdk,
            toolchainBundleID: toolchainBundleID,
            using: runner
        ).map { artifactURL in
            BypassRebuilder(
                capturingBuild: CapturingWasmBuildInvocation(
                    swiftExecutable: swift,
                    projectPath: projectURL,
                    swiftSDK: sdk,
                    toolchainBundleID: toolchainBundleID
                ),
                // Correctness fallback: the same full `swift package js` build the
                // initial build uses — it emits a browser-ready reactor wasm.
                fullBuild: invocation,
                appModule: "App",
                projectPath: projectURL,
                appSourcesDir: projectURL.appendingPathComponent("Sources/App"),
                manifestURL: projectURL.appendingPathComponent("Package.swift"),
                resolvedURL: projectURL.appendingPathComponent("Package.resolved"),
                artifactURL: artifactURL,
                outputWasmURL: outputWasmURL
            )
        }
        if bypassRebuilder == nil {
            print("swiflow: fast rebuild unavailable (could not resolve the wasm bin path); using full packaging per save.")
        }

        // 5. Start the dev server.
        let server = DevServer(projectRoot: projectURL, port: port)
        print("swiflow: dev server listening on http://localhost:\(port)")

        // 6. Start the file watcher in a background task. Per-file-type
        //    dispatch: Swift changes rebuild and hot-swap the wasm bundle
        //    in place; HTML/JS changes reload the page so static assets are
        //    refetched; mixed batches rebuild and reload. Decision §2: don't
        //    broadcast on failed rebuilds.
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
                // ProcessRunner is intentionally non-Sendable; this task gets
                // its own stateless runner. `state` persists across saves and
                // is owned solely by this serial loop (no cross-task sharing) —
                // do NOT parallelize this loop (it would corrupt shared swiftc
                // incremental state in .build).
                let rebuildRunner = SystemProcessRunner()
                var state = BypassState()
                for await changed in watcher.changes() {
                    let dispatch = Self.changeDispatch(for: changed)
                    print("swiflow: \(dispatch.rebuild ? "rebuilding" : "reloading") (\(changed.count) file\(changed.count == 1 ? "" : "s") changed)...")
                    do {
                        if dispatch.rebuild {
                            if let bypassRebuilder {
                                try bypassRebuilder.rebuild(using: rebuildRunner, state: &state)
                            } else {
                                _ = try invocation.run(using: rebuildRunner)
                            }
                        }
                        switch dispatch.broadcast {
                        case .hmrSwap:
                            let bust = Self.wasmCacheBusterSuffix(projectURL: projectURL)
                            await server.hub.broadcastHMRSwap(
                                wasmURL: "/\(Self.packageToJSOutputRelativePath)/App.wasm?h=\(bust)",
                                jsURL: "/\(Self.packageToJSOutputRelativePath)/index.js?h=\(bust)"
                            )
                            print("swiflow: HMR broadcast")
                        case .reload:
                            await server.hub.broadcastReload()
                            print("swiflow: reload broadcast")
                        }
                    } catch {
                        print("swiflow: rebuild failed — \(error). Browser unchanged; fix and save to retry.")
                    }
                }
            }
            try await group.next()
            group.cancelAll()
        }
    }

    /// What to do for a batch of changed files. Pure — unit-tested directly.
    struct ChangeDispatch: Equatable {
        enum Broadcast: Equatable { case hmrSwap, reload }
        let rebuild: Bool
        let broadcast: Broadcast

        init(rebuild: Bool, broadcast: Broadcast) {
            self.rebuild = rebuild
            self.broadcast = broadcast
        }
    }

    /// Swift edits need a rebuild and can hot-swap the wasm in place.
    /// HTML/JS edits are static-asset changes: the page itself must reload
    /// to refetch them (hmr-swap only re-imports the wasm bundle — it never
    /// refetches index.html). Mixed batches rebuild AND reload, which picks
    /// up both.
    static func changeDispatch(for changed: Set<URL>) -> ChangeDispatch {
        let swiftChanged = changed.contains { $0.pathExtension == "swift" }
        let webChanged = changed.contains { $0.pathExtension != "swift" }
        switch (swiftChanged, webChanged) {
        case (true, false): return .init(rebuild: true, broadcast: .hmrSwap)
        case (true, true):  return .init(rebuild: true, broadcast: .reload)
        default:            return .init(rebuild: false, broadcast: .reload)
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
