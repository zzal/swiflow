// Sources/SwiflowCLI/Toolchain/SwiftContext.swift
//
// One owner for the swiftc invocation preamble.
// ToolchainResolution centralized RESOLUTION — which `swift`, which SDK,
// which TOOLCHAINS bundle — after that preamble had drifted once. But only
// resolution was centralized: the INVOCATION side (the TOOLCHAINS env map,
// the project working directory, the executable) was still composed
// independently at three sites (BuildInvocation, CapturingWasmBuild-
// Invocation, WasmArtifactLocator), the exact drift class that produced
// the command-vs-reactor-ABI incident. This type composes it once; the
// invocation types keep their argv policy and delegate the preamble here.
//
// Deliberately NOT in scope: CommandReplayer. It replays commands captured
// verbatim from SwiftPM's own verbose output — absolute toolchain paths
// baked in, no TOOLCHAINS needed — so forcing it through this preamble
// would be wrong, not just unnecessary.

import Foundation

struct SwiftContext: Sendable {
    let swift: URL
    let projectPath: URL
    let sdk: String
    let toolchainBundleID: String?

    init(swift: URL, projectPath: URL, sdk: String, toolchainBundleID: String?) {
        self.swift = swift
        self.projectPath = projectPath
        self.sdk = sdk
        self.toolchainBundleID = toolchainBundleID
    }

    /// The usual construction: a `ToolchainResolution` pinned to a project.
    init(resolution: ToolchainResolution.Result, projectPath: URL) {
        self.init(
            swift: resolution.swift,
            projectPath: projectPath,
            sdk: resolution.sdk,
            toolchainBundleID: resolution.toolchainBundleID
        )
    }

    /// The TOOLCHAINS env map — composed here and nowhere else. On macOS
    /// this points SwiftPM's driver at the swift.org toolchain's clang
    /// (the Xcode default has no WASM backend); nil means "inherit".
    var environment: [String: String]? {
        toolchainBundleID.map { ["TOOLCHAINS": $0] }
    }

    /// Runs `swift <arguments>` in the project directory with the toolchain
    /// environment — the shared preamble under every invocation shape.
    @discardableResult
    func run(
        _ arguments: [String],
        using runner: ProcessRunner,
        captureOutput: Bool
    ) throws -> ProcessResult {
        try runner.run(
            executable: swift,
            arguments: arguments,
            workingDirectory: projectPath,
            environment: environment,
            captureOutput: captureOutput
        )
    }
}
