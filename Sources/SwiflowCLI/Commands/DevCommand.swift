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
        //      shared with `swiflow build` (see ToolchainResolution). The
        //      resolved context owns the invocation preamble for the initial
        //      build, the bin-path query, and every capture rebuild below.
        let resolution = try ToolchainResolution.resolve(swiftSDKOverride: swiftSDK, using: runner)
        let context = SwiftContext(resolution: resolution, projectPath: projectURL)

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
            context: context,
            configuration: .dev,
            compileCacheDir: compileCacheDir
        )
        // A missing .build/ means SwiftPM still has to resolve dependencies
        // and compile every module from scratch — minutes of silence that
        // look like a hang without the expectation line.
        let coldBuild = !FileManager.default.fileExists(
            atPath: projectURL.appendingPathComponent(".build").path)
        print(Self.initialBuildStatus(cold: coldBuild))
        let buildClock = ContinuousClock()
        let buildStart = buildClock.now
        do {
            _ = try invocation.run(using: runner)
        } catch let error as BuildCommandError {
            throw ValidationError(String(describing: error))
        }
        print(Self.initialBuildCompleted(elapsed: buildClock.now - buildStart))

        // 4.5 Build the bypass rebuilder. The dev loop replays SwiftPM's own
        //     swiftc + wasm-ld commands per save (~1.6s), re-capturing them via
        //     a full `swift build` whenever the app source/import set or the
        //     manifest changes. If the wasm bin path can't be resolved we leave
        //     it nil and fall back to the full `swift package js` per save.
        let outputWasmURL = projectURL
            .appendingPathComponent(Self.packageToJSOutputRelativePath)
            .appendingPathComponent("App.wasm")
        let bypassRebuilder: BypassRebuilder? = WasmArtifactLocator.resolve(
            context: context,
            using: runner
        ).map { artifactURL in
            BypassRebuilder(
                capturingBuild: CapturingWasmBuildInvocation(context: context),
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
                //
                // The wrapper captures every child's output so a failed
                // rebuild's compiler diagnostics can be forwarded to the
                // browser overlay (streaming callers get a post-exit echo
                // instead of live output — see DiagnosticsRecordingRunner).
                let rebuildRunner = DiagnosticsRecordingRunner(base: SystemProcessRunner())
                var state = BypassState()
                let loopClock = ContinuousClock()
                for await changed in watcher.changes() {
                    let dispatch = Self.changeDispatch(for: changed)
                    print(Self.loopStatus(dispatch: dispatch, changedCount: changed.count))
                    rebuildRunner.reset()
                    do {
                        var rebuildElapsed: Duration?
                        if dispatch.rebuild {
                            let rebuildStart = loopClock.now
                            if let bypassRebuilder {
                                try bypassRebuilder.rebuild(using: rebuildRunner, state: &state)
                            } else {
                                _ = try invocation.run(using: rebuildRunner)
                            }
                            rebuildElapsed = loopClock.now - rebuildStart
                        }
                        switch dispatch.broadcast {
                        case .hmrSwap:
                            let bust = Self.wasmCacheBusterSuffix(projectURL: projectURL)
                            await server.hub.broadcastHMRSwap(
                                wasmURL: "/\(Self.packageToJSOutputRelativePath)/App.wasm?h=\(bust)",
                                jsURL: "/\(Self.packageToJSOutputRelativePath)/index.js?h=\(bust)"
                            )
                        case .reload:
                            await server.hub.broadcastReload()
                        }
                        print(Self.loopCompletion(
                            broadcast: dispatch.broadcast, rebuildElapsed: rebuildElapsed))
                    } catch {
                        print(Self.rebuildFailed(reason: String(describing: error)))
                        // Forward the compiler output's tail to the browser —
                        // the page keeps running the last successful build,
                        // and without the overlay that staleness is invisible
                        // (decision §2 still holds: no reload/hmr broadcast
                        // on failure).
                        await server.hub.broadcastBuildError(message: Self.buildErrorTail(
                            diagnostics: rebuildRunner.lastFailureOutput,
                            fallback: String(describing: error)))
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

    // MARK: - Status messages
    //
    // One action-first voice across the loop — rebuilding… / hot-swapped /
    // reloaded / rebuild failed — <reason> — instead of the mixed tense +
    // internal jargon ("HMR broadcast") these lines once had. Pure statics
    // (like `changeDispatch`) so the voice is test-pinnable.

    /// The initial-build announcement. A cold build (no `.build/` yet) adds
    /// an expectation-setting line: dependency resolution + a full WASM
    /// compile can run for minutes with no output, and without the warning
    /// that silence reads as a hang.
    static func initialBuildStatus(cold: Bool) -> String {
        var lines = ["swiflow: building (dev configuration)..."]
        if cold {
            lines.append("swiflow: first build resolves dependencies and compiles to WASM — this can take a few minutes")
        }
        return lines.joined(separator: "\n")
    }

    static func initialBuildCompleted(elapsed: Duration) -> String {
        "swiflow: built in \(formatElapsed(elapsed))"
    }

    static func loopStatus(dispatch: ChangeDispatch, changedCount: Int) -> String {
        "swiflow: \(dispatch.rebuild ? "rebuilding" : "reloading") (\(changedCount) file\(changedCount == 1 ? "" : "s") changed)..."
    }

    /// `rebuildElapsed` is the save-to-swap latency — nil for static-asset
    /// reloads, where nothing was rebuilt and a stamp would be noise.
    static func loopCompletion(broadcast: ChangeDispatch.Broadcast, rebuildElapsed: Duration?) -> String {
        let verb: String
        switch broadcast {
        case .hmrSwap: verb = "hot-swapped"
        case .reload:  verb = "reloaded"
        }
        guard let rebuildElapsed else { return "swiflow: \(verb)" }
        return "swiflow: \(verb) in \(formatElapsed(rebuildElapsed))"
    }

    static func rebuildFailed(reason: String) -> String {
        "swiflow: rebuild failed — \(reason). Error shown in the browser overlay; fix and save to retry."
    }

    /// The compiler-output excerpt forwarded to the browser overlay.
    ///
    /// Anchored at the FIRST `error:` line: `swift build` routes compiler
    /// diagnostics through stdout while stderr ends with kilobytes of
    /// manifest/dependency chatter, so a naive last-N-lines tail of the
    /// combined output ships pure noise (live-smoke-verified). From the
    /// anchor we keep content FORWARD — root cause first, notes after —
    /// and the caps keep a megabyte of `-v` spew from becoming the
    /// WebSocket frame. No recognizable error line → plain tail, which at
    /// least ends where the process gave up.
    static func buildErrorTail(
        diagnostics: String?,
        fallback: String,
        maxLines: Int = 120,
        maxBytes: Int = 16_384
    ) -> String {
        guard let diagnostics,
              !diagnostics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return fallback
        }
        // Strip ANSI color escapes BEFORE anchoring: swiftc emits them even
        // into a pipe, they render as garbage in the overlay, and one sits
        // right between ": " and "error:" — hiding the line from the anchor
        // (live-smoke-verified).
        let plain = diagnostics.replacingOccurrences(
            of: "\u{001B}\\[[0-9;]*m", with: "", options: .regularExpression)
        // swiftc's format is "file:line:col: error: msg"; SwiftPM's own is
        // "error: msg". Requiring the marker at line start or after ": "
        // keeps single-line argv dumps (which mention flags like
        // -serialize-diagnostics-path) from anchoring the excerpt on noise.
        func isErrorLine(_ line: Substring) -> Bool {
            line.hasPrefix("error:") || line.contains(": error:")
        }
        let lines = plain.split(separator: "\n", omittingEmptySubsequences: false)
        var excerpt: String
        let keepHeadOnByteCap: Bool
        if let anchor = lines.firstIndex(where: isErrorLine) {
            excerpt = lines[anchor...].prefix(maxLines).joined(separator: "\n")
            keepHeadOnByteCap = true
        } else {
            excerpt = lines.suffix(maxLines).joined(separator: "\n")
            keepHeadOnByteCap = false
        }
        if excerpt.utf8.count > maxBytes {
            // Cap on the side holding the signal; a split code point at the
            // cut becomes a replacement character, fine for a dev overlay.
            let bytes = keepHeadOnByteCap
                ? Array(excerpt.utf8.prefix(maxBytes))
                : Array(excerpt.utf8.suffix(maxBytes))
            excerpt = String(decoding: bytes, as: UTF8.self)
        }
        return excerpt
    }

    /// "12.3s" under a minute, "3m 42s" from there up.
    static func formatElapsed(_ duration: Duration) -> String {
        let totalSeconds = Double(duration.components.seconds)
            + Double(duration.components.attoseconds) / 1e18
        guard totalSeconds >= 60 else { return String(format: "%.1fs", totalSeconds) }
        let whole = Int(totalSeconds)
        return "\(whole / 60)m \(whole % 60)s"
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
