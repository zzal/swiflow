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
        name: .customLong("template"),
        help: ArgumentHelp(
            "Which embedded template to scaffold. Defaults to HelloWorld.",
            discussion: """
                Run `swiflow init --help` for the current list of available templates.
                Each name maps to a directory under examples/ in the Swiflow repo.
                """
        )
    )
    var template: String = "HelloWorld"

    @Option(
        name: .customLong("swiflow-source"),
        help: ArgumentHelp(
            "Local path the generated project uses for its Swiflow dependency.",
            discussion: """
                Override the default versioned URL dep with a path to a local Swiflow \
                clone — for hacking on Swiflow itself, not for end-user projects.
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
            "Override the Swiflow release the generated project pins to.",
            discussion: """
                Without this flag, the generated Package.swift pins to the version of \
                this CLI binary. Use --swiflow-version to pin to a different published \
                tag (e.g. an older release for compatibility, or a newer one when this \
                CLI lags the framework).
                Example: --swiflow-version 0.1.3
                """
        )
    )
    var swiflowVersion: String?

    func run() async throws {
        // Dep resolution precedence (most→least explicit):
        //   1. --swiflow-version <v>                 → versioned URL dep
        //   2. --swiflow-source / $SWIFLOW_SOURCE    → local path dep (dev mode)
        //   3. neither                                → versioned URL dep pinned
        //                                              to this CLI's own version
        //
        // Default (3) Just Works for end users once a release is published:
        // `swiflow init my-app` generates a Package.swift pinned to the
        // matching `swiflow` release tag. Contributors hacking on Swiflow
        // itself pass --swiflow-source to point at their checkout.
        // Treat an empty `--swiflow-source ""` or `SWIFLOW_SOURCE=""` as
        // unset — otherwise a shell idiom like `SWIFLOW_SOURCE= swiflow init …`
        // (commonly used to clear an inherited env var) would silently
        // generate `.package(path: "")` instead of falling through to the
        // default versioned URL.
        let rawSource = swiflowSource
            ?? ProcessInfo.processInfo.environment["SWIFLOW_SOURCE"]
        let source = (rawSource?.isEmpty == false) ? rawSource : nil

        let dep: SwiflowDep
        if let version = swiflowVersion {
            dep = .url(SwiflowDep.officialRepositoryURL, version: version)
        } else if let source {
            dep = .path(source)
        } else {
            dep = .url(SwiflowDep.officialRepositoryURL, version: SwiflowVersion.current)
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

        guard let chosenTemplate = EmbeddedTemplates.lookup(template) else {
            let names = EmbeddedTemplates.availableNames.joined(separator: ", ")
            throw ValidationError(#"unknown template "\#(template)" — available: \#(names)"#)
        }

        do {
            try ProjectWriter.writeProject(
                name: name,
                template: chosenTemplate,
                into: parentURL,
                swiflowDep: dep,
                jsDriverSource: EmbeddedDriver.javascriptSource,
                jsServiceWorkerSource: EmbeddedDriver.serviceWorkerSource
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
