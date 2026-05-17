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
    case swiftPackageJSFailed(exitCode: Int32)
    case projectPathNotFound(URL)

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
        case .swiftPackageJSFailed(let code):
            return "swift package js failed with exit code \(code). See output above."
        case .projectPathNotFound(let url):
            return "project path does not exist or is not a directory: \(url.path)"
        }
    }
}

/// Pure argv-composition + Process invocation. BuildCommand.run() delegates here.
struct BuildInvocation {
    let swiftExecutable: URL
    let projectPath: URL
    let swiftSDK: String
    let toolchainBundleID: String?

    /// Runs `swift package --swift-sdk <id> js --use-cdn --product App -c release`
    /// in `projectPath`. Inherits stdout/stderr so the user sees swift's progress.
    @discardableResult
    func run(using runner: ProcessRunner) throws -> ProcessResult {
        let arguments = [
            "package",
            "--swift-sdk", swiftSDK,
            "js",
            "--use-cdn",
            "--product", "App",
            "-c", "release",
        ]

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
            let installed = try probe.list()
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

        print("""
            swiflow: build complete.
              Output:  .build/plugins/PackageToJS/outputs/Package/
              Serve:   python3 -m http.server 3000  (from \(projectURL.path))
            """)
    }
}
