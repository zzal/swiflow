// Sources/SwiflowCLI/Commands/BuildCommand.swift
//
// `swiflow build` — composes WasmSDKProbe + MacToolchainProbe +
// ProcessRunner to invoke `swift package ... js --use-cdn --product App
// -c release` against the user's project.
//
// BuildInvocation is the pure argv-composition + Process invocation step;
// it's split from BuildCommand so unit tests can drive it without parsing
// ArgumentParser's argv.

import ArgumentParser
import Foundation

enum BuildCommandError: Error, Equatable, CustomStringConvertible {
    case swiftNotOnPath
    case noWasmSDKInstalled
    case wasmSDKListFailed(exitCode: Int32, stderr: String?)
    case swiftPackageJSFailed(exitCode: Int32)
    case swiftBuildFailed(exitCode: Int32)
    case projectPathNotFound(URL)
    case manifestArtifactMissing(URL)

    var description: String {
        switch self {
        case .swiftNotOnPath:
            return "swift is not on PATH. Install Swift from https://swift.org/install and try again."
        case .noWasmSDKInstalled:
            return """
                No WASM Swift SDK is installed. Run:
                    swift sdk install <SDK URL for your Swift version>
                with a URL from https://swift.org/install (look for the WebAssembly SDK).
                """
        case .wasmSDKListFailed(let code, let stderr):
            let trimmed = stderr?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let trailer = trimmed.isEmpty ? "" : "\n\nDetails from swift:\n\(trimmed)"
            return """
                `swift sdk list` failed with exit code \(code). \
                Your Swift toolchain may not support the `sdk` subcommand \
                (it landed in Swift 5.9). Verify with `swift --version`.\(trailer)
                """
        case .swiftPackageJSFailed(let code):
            return "swift package js failed with exit code \(code). See output above."
        case .swiftBuildFailed(let code):
            return "swift build failed with exit code \(code). See output above."
        case .projectPathNotFound(let url):
            return "project path does not exist or is not a directory: \(url.path)"
        case .manifestArtifactMissing(let url):
            return "swiflow: manifest artifact missing after build: \(url.path)"
        }
    }
}

/// `swiflow build` and `swiflow dev` invoke the same SwiftPM plugin
/// (`swift package js`) but with different shapes. Release flips on
/// `-c release` for `wasm-opt`-friendly output; dev keeps optimisations
/// off and asks the toolchain to embed DWARF debug symbols so a Chrome
/// C/C++ DevTools extension can map traps back to Swift source lines.
enum BuildConfiguration: Equatable {
    case release
    case dev
}

/// Pure argv-composition + Process invocation. BuildCommand.run() delegates here.
struct BuildInvocation {
    let swiftExecutable: URL
    let projectPath: URL
    let swiftSDK: String
    let toolchainBundleID: String?
    let configuration: BuildConfiguration

    init(
        swiftExecutable: URL,
        projectPath: URL,
        swiftSDK: String,
        toolchainBundleID: String?,
        configuration: BuildConfiguration = .release
    ) {
        self.swiftExecutable = swiftExecutable
        self.projectPath = projectPath
        self.swiftSDK = swiftSDK
        self.toolchainBundleID = toolchainBundleID
        self.configuration = configuration
    }

    /// Composes the `swift package js` argv without side effects.
    /// `.release` appends `-c release` plus `-Xswiftc -Osize` and
    /// `-Xswiftc -gnone` (size-over-speed optimisation; debug info
    /// dropped — not needed in production bundles).
    /// `.dev` appends `--debug-info-format dwarf` so the WASM build carries
    /// DWARF debug symbols for the Phase 13b Chrome DevTools story.
    func composeArguments() -> [String] {
        // Base: swift package global flags (--swift-sdk, -Xswiftc etc.) come
        // before the plugin subcommand `js`; the plugin's own flags (-c, --use-cdn,
        // --product, --debug-info-format) come after it.
        var prePluginArgs: [String] = [
            "package",
            "--swift-sdk", swiftSDK,
        ]
        var pluginArgs: [String] = [
            "js",
            "--use-cdn",
            "--product", "App",
        ]
        switch configuration {
        case .release:
            // -Osize asks the Swift compiler to optimise for size rather than
            // speed — a better trade-off for DOM-diffing workloads that don't
            // do numerical compute. -gnone drops debug info in release (dev
            // still ships DWARF via --debug-info-format dwarf below).
            // -Xswiftc is a swift-package global option and must precede `js`.
            // -disable-reflection-metadata: all Mirror call sites were removed in
            // Phase 15 Task 6, so the linker can now dead-strip the demangler and
            // SIMD debugDescription helpers that Mirror references pin. Dev builds
            // keep reflection metadata for Phase 13b DWARF debugging.
            prePluginArgs.append(contentsOf: [
                "-Xswiftc", "-Osize",
                "-Xswiftc", "-gnone",
                "-Xswiftc", "-disable-reflection-metadata",
            ])
            pluginArgs.append(contentsOf: ["-c", "release"])
        case .dev:
            // Dev mode: no -c release (default is debug). Ask the
            // PackageToJS plugin to keep DWARF in the final wasm so trap
            // stack frames carry Swift file:line info that Chrome's
            // C/C++ DevTools extension can resolve. The plugin's own
            // --debug-info-format option is the only path; -Xswiftc -g
            // isn't forwarded by the plugin (it errors with
            // "Unexpected arguments: -Xswiftc -g").
            pluginArgs.append(contentsOf: ["--debug-info-format", "dwarf"])
        }
        return prePluginArgs + pluginArgs
    }

    /// Runs `swift package --swift-sdk <id> js --use-cdn --product App ...`
    /// in `projectPath`. Inherits stdout/stderr so the user sees swift's progress.
    /// Delegates argv composition to `composeArguments()`.
    @discardableResult
    func run(using runner: ProcessRunner) throws -> ProcessResult {
        let arguments = composeArguments()

        let environment: [String: String]? = {
            guard let bundleID = toolchainBundleID else { return nil }
            return ["TOOLCHAINS": bundleID]
        }()

        let result = try runner.run(
            executable: swiftExecutable,
            arguments: arguments,
            workingDirectory: projectPath,
            environment: environment,
            captureOutput: false
        )

        if result.exitCode != 0 {
            throw BuildCommandError.swiftPackageJSFailed(exitCode: result.exitCode)
        }
        return result
    }
}

struct BuildCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "build",
        abstract: "Build a Swiflow project to a browser-loadable WASM bundle."
    )

    @Option(
        name: .customLong("path"),
        help: "Path to the Swiflow project directory. Defaults to the current working directory."
    )
    var path: String = "."

    @Option(
        name: .customLong("swift-sdk"),
        help: ArgumentHelp(
            "Override the Swift WASM SDK identifier.",
            discussion: """
                When unset, swiflow runs `swift sdk list` and picks the first installed \
                WASM SDK. Use this flag to pin to a specific SDK across machines.
                """
        )
    )
    var swiftSDK: String?

    func run() async throws {
        let runner = SystemProcessRunner()

        // 0. Validate --path early so we emit a clean error instead of letting
        //    Process.run() surface a raw Cocoa "file doesn't exist" error.
        let projectURL = URL(fileURLWithPath: path).standardizedFileURL
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: projectURL.path, isDirectory: &isDir), isDir.boolValue else {
            throw ValidationError(String(describing: BuildCommandError.projectPathNotFound(projectURL)))
        }

        // 1. Find swift on PATH.
        guard let swift = try SwiftExecutableLocator.locate(using: runner) else {
            throw ValidationError(String(describing: BuildCommandError.swiftNotOnPath))
        }

        // 2. Resolve the WASM SDK ID — either user-supplied or auto-picked.
        let sdk: String
        if let userSDK = swiftSDK {
            sdk = userSDK
        } else {
            let probe = WasmSDKProbe(runner: runner, swiftExecutable: swift)
            let installed: [String]
            do {
                installed = try probe.list()
            // Case-pattern catch (vs. `catch let error as WasmSDKProbeError`)
            // because we destructure the payload to translate it into the
            // BuildCommand-scoped error vocabulary. The `as`-cast form below
            // (line ~168) is used when we re-wrap the same error type — pick
            // the case-pattern when payload translation is the point.
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

        // 3. macOS: detect TOOLCHAINS bundle ID if not already set.
        let toolchainBundleID: String?
        if ProcessInfo.processInfo.environment["TOOLCHAINS"] != nil {
            // Respect the user's pin.
            toolchainBundleID = nil
        } else {
            toolchainBundleID = MacToolchainProbe.swiftLatestBundleIdentifier()
        }

        // 4. Run the build.
        let invocation = BuildInvocation(
            swiftExecutable: swift,
            projectPath: projectURL,
            swiftSDK: sdk,
            toolchainBundleID: toolchainBundleID
        )

        print("swiflow: building with swift-sdk=\(sdk)\(toolchainBundleID.map { " toolchain=\($0)" } ?? "")")
        do {
            _ = try invocation.run(using: runner)
        } catch let error as BuildCommandError {
            throw ValidationError(String(describing: error))
        }

        // 5. Ensure the embedded JS driver + service worker are at the project
        //    root for static hosting. `swiflow init` scaffolds them, but a
        //    project that wasn't init-ed would otherwise have no driver to load
        //    App.wasm. Re-emitting keeps them in lockstep with this CLI version.
        try DriverInstaller.install(into: projectURL)

        // 6. Write swiflow-manifest.json at the project root, where swiflow-sw.js
        //    expects to find it (new URL("swiflow-manifest.json", self.location.href)
        //    resolves to the SW's own scope, which is the project root).
        try BuildCommand.writeManifest(projectDir: projectURL)
        print("swiflow: manifest written → swiflow-manifest.json")

        print("""
            swiflow: build complete.
              Output:  .build/plugins/PackageToJS/outputs/Package/
              Serve:   python3 -m http.server 3000  (from \(projectURL.path))
            """)
    }

    /// Builds `swiflow-manifest.json` from the PackageToJS output artifacts and
    /// writes it at `projectDir/swiflow-manifest.json` — alongside `swiflow-sw.js`,
    /// where the service worker resolves it (the SW does
    /// `new URL("swiflow-manifest.json", self.location.href)`, which resolves
    /// against its own scope = the project root).
    ///
    /// Artifact URLs in the manifest carry the PackageToJS output-dir prefix
    /// (`.build/plugins/PackageToJS/outputs/Package/`) so they resolve to the
    /// real artifact paths under the same scope.
    ///
    /// Extracted from `run()` so tests can invoke the real production manifest-write
    /// path after running the build step independently — without having to re-invoke
    /// `BuildCommand.run()` and repeat the full WASM compilation.
    package static func writeManifest(projectDir: URL) throws {
        let outputDir = projectDir.appendingPathComponent(".build/plugins/PackageToJS/outputs/Package")
        let outputPrefix = ".build/plugins/PackageToJS/outputs/Package/"

        let wasmURL = outputDir.appendingPathComponent("App.wasm")
        guard FileManager.default.fileExists(atPath: wasmURL.path) else {
            throw BuildCommandError.manifestArtifactMissing(wasmURL)
        }
        let wasmEntry = BundleManifest.Entry.computing(
            url: outputPrefix + "App.wasm",
            from: try Data(contentsOf: wasmURL)
        )

        let runtimeRelPaths = ["index.js", "instantiate.js", "runtime.js", "platforms/browser.js"]
        let runtimeEntries: [BundleManifest.Entry] = try runtimeRelPaths.map { rel in
            let artifactURL = outputDir.appendingPathComponent(rel)
            guard FileManager.default.fileExists(atPath: artifactURL.path) else {
                throw BuildCommandError.manifestArtifactMissing(artifactURL)
            }
            return BundleManifest.Entry.computing(
                url: outputPrefix + rel,
                from: try Data(contentsOf: artifactURL)
            )
        }

        let manifest = BundleManifest(version: "1", wasm: wasmEntry, runtime: runtimeEntries)
        try manifest.encoded().write(
            to: projectDir.appendingPathComponent("swiflow-manifest.json"),
            options: .atomic
        )
    }
}
