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
                Example: --swiflow-source /path/to/swiflow
                """
        )
    )
    var swiflowSource: String?

    mutating func validate() throws {
        if swiflowSource == nil {
            throw ValidationError("""
                --swiflow-source is required. Swiflow has no public release yet.
                Pass the path to your local Swiflow clone:
                  swiflow init \(name) --swiflow-source /path/to/swiflow
                """)
        }
    }

    func run() async throws {
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
                swiflowSource: swiflowSource!,   // validate() guarantees non-nil
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
