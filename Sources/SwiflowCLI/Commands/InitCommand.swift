// Sources/SwiflowCLI/Commands/InitCommand.swift
//
// `swiflow init <name>` — scaffolds a new Swiflow project from the embedded
// templates + driver into a directory of `<name>` underneath `--into`
// (defaults to CWD). `init` takes `--into` (the PARENT to scaffold into),
// while `build`/`dev` take `--path` (the project directory itself) — the
// distinct names keep the two meanings from being confused:
//
//     swiflow init demo --into /tmp
//     swiflow build --path /tmp/demo
//     swiflow dev   --path /tmp/demo

import ArgumentParser
import Foundation

enum InitCommandError: Error, Equatable, CustomStringConvertible {
    case parentPathNotFound(URL)
    case invalidProjectName(String)

    var description: String {
        switch self {
        case .parentPathNotFound(let url):
            return "parent path does not exist or is not a directory: \(url.path)"
        case .invalidProjectName(let name):
            return #"invalid project name "\#(name)" — project name must be a plain directory name (no "/", and not "." or ".."), e.g. MyApp"#
        }
    }
}

/// Guards `ProjectWriter.writeProject(name:...)` (which does a bare
/// `parent.appendingPathComponent(name)`) against names that escape the
/// chosen `--into` parent. Rejects any path separator (so `a/b`, `../evil`,
/// and absolute-looking names like `/etc/passwd` are all caught by the same
/// check) and the two dot-directory names that resolve to the parent itself
/// or its parent. A small pure function so the validation is unit-testable
/// without invoking the full command.
func isValidProjectName(_ name: String) -> Bool {
    guard !name.isEmpty, name != ".", name != ".." else { return false }
    return !name.contains("/")
}

struct InitCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Scaffold a new Swiflow project."
    )

    @Argument(help: "The project name. A directory of this name will be created inside --into (CWD by default).")
    var name: String

    @Option(
        name: .customLong("into"),
        help: "Parent directory to scaffold the project into. Defaults to the current working directory. (Note: `build`/`dev` take --path — the project directory itself.)"
    )
    var into: String = "."

    @Option(
        name: .customLong("template"),
        help: ArgumentHelp(
            "Which embedded template to scaffold. Defaults to HelloWorld.",
            discussion: """
                Available: \(EmbeddedTemplates.availableNames.joined(separator: ", ")).
                A curated subset of the repo's examples/ directory — some examples
                (RegionDemo, AsyncFetch, MiniRouter) exist for reading, not scaffolding.
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
        // Reject names that would let ProjectWriter's bare
        // `parent.appendingPathComponent(name)` escape --into (e.g.
        // "../../evil") or silently nest (e.g. "a/b/c"). Checked first,
        // before any filesystem work, so a bad name never touches disk.
        guard isValidProjectName(name) else {
            throw ValidationError(String(describing: InitCommandError.invalidProjectName(name)))
        }

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

        // Resolve --into against CWD when relative (so `--into .` and a bare
        // invocation both land in the working directory the user expects).
        // standardizedFileURL collapses `..` segments so error messages and
        // the "cd <path>" hint print clean paths instead of "/tmp/foo/./".
        let parentURL = URL(fileURLWithPath: into).standardizedFileURL
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
                jsServiceWorkerSource: EmbeddedDriver.serviceWorkerSource,
                jsRegionsSource: EmbeddedDriver.regionsSource,
                jsGuestSdkSource: EmbeddedDriver.guestSdkSource
            )
        } catch let error as ProjectWriterError {
            throw ValidationError(String(describing: error))
        }

        let projectPath = parentURL.appendingPathComponent(name).path
        print(Self.nextSteps(projectPath: projectPath))
    }

    /// The post-scaffold guidance. Doctor is deliberately step 0: a
    /// first-timer without the WASM SDK should learn the toolchain check
    /// exists BEFORE `swiflow dev`'s first cryptic build failure, not after.
    /// The serve suggestion deliberately does NOT chain anything after
    /// `http.server` — the server blocks in the foreground, so a chained
    /// `open` would never run; the URL is a comment instead. Extracted (not
    /// inline in `run`) so tests can pin both properties.
    static func nextSteps(projectPath: String) -> String {
        """
        Created \(projectPath)
          Next steps:
            swiflow doctor   # first time? verify the toolchain (Swift + WASM SDK)
            cd \(projectPath)
            swiflow dev
            # or:
            swiflow build && python3 -m http.server 3000
            # then browse to http://localhost:3000
        """
    }
}
