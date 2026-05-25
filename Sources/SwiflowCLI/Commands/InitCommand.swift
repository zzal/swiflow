// Sources/SwiflowCLI/Commands/InitCommand.swift
//
// `swiflow init <name>` — scaffolds a new Swiflow project from the embedded
// templates + driver into a directory of `<name>` underneath `--path`
// (defaults to CWD). The `--path` flag mirrors what `build` and `dev`
// accept, so the three commands compose naturally:
//
//     swiflow init demo --path /tmp
//     swiflow build --path /tmp/demo
//     swiflow dev   --path /tmp/demo

import ArgumentParser
import Foundation

enum InitCommandError: Error, Equatable, CustomStringConvertible {
    case parentPathNotFound(URL)

    var description: String {
        switch self {
        case .parentPathNotFound(let url):
            return "parent path does not exist or is not a directory: \(url.path)"
        }
    }
}

struct InitCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Scaffold a new Swiflow project."
    )

    @Argument(help: "The project name. A directory of this name will be created under --path (CWD by default).")
    var name: String

    @Option(
        name: .customLong("path"),
        help: "Parent directory in which to create the project. Defaults to the current working directory."
    )
    var path: String = "."

    @Option(
        name: .customLong("swiflow-source"),
        help: ArgumentHelp(
            "Path the generated project uses for its Swiflow dependency.",
            discussion: """
                Required until Swiflow has a public release. Pass the absolute or \
                relative path to your local Swiflow clone.
                Examples:
                  --swiflow-source /path/to/swiflow   (absolute)
                  --swiflow-source ../swiflow         (relative to the project parent dir)
                """
        )
    )
    var swiflowSource: String?

    @Option(
        name: .customLong("swiflow-version"),
        help: ArgumentHelp(
            "Version of Swiflow to depend on via URL (e.g. 1.0.0).",
            discussion: """
                When provided, the generated Package.swift uses a versioned URL dependency \
                on the official Swiflow GitHub release instead of a local path.
                Example: --swiflow-version 1.0.0
                """
        )
    )
    var swiflowVersion: String?

    func run() async throws {
        let dep: SwiflowDep
        if let version = swiflowVersion {
            dep = .url(SwiflowDep.officialRepositoryURL, version: version)
        } else if let source = swiflowSource ?? ProcessInfo.processInfo.environment["SWIFLOW_SOURCE"] {
            dep = .path(source)
        } else {
            throw ValidationError("""
                --swiflow-source is required. Swiflow has no public release yet.
                Pass the path to your local Swiflow clone:
                  swiflow init \(name) --swiflow-source /path/to/swiflow
                Or set the SWIFLOW_SOURCE environment variable.

                (--swiflow-version <version> is forward-looking infrastructure — it generates a
                versioned URL dep, but won't resolve until the first public release lands.
                Pre-release: use --swiflow-source.)
                """)
        }

        // Resolve --path against CWD when relative (so `--path .` and a bare
        // invocation both land in the working directory the user expects).
        // standardizedFileURL collapses `..` segments so error messages and
        // the "cd <path>" hint print clean paths instead of "/tmp/foo/./".
        let parentURL = URL(fileURLWithPath: path).standardizedFileURL
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: parentURL.path, isDirectory: &isDir), isDir.boolValue else {
            throw ValidationError(String(describing: InitCommandError.parentPathNotFound(parentURL)))
        }

        do {
            try ProjectWriter.writeProject(
                name: name,
                into: parentURL,
                swiflowDep: dep,
                jsDriverSource: EmbeddedDriver.javascriptSource
            )
        } catch let error as ProjectWriterError {
            throw ValidationError(String(describing: error))
        }

        let projectPath = parentURL.appendingPathComponent(name).path
        print("""
            Created \(projectPath)
              Next steps:
                cd \(projectPath)
                swiflow dev
                # or:
                swiflow build && python3 -m http.server 3000 && open http://localhost:3000
            """)
    }
}
