// Sources/SwiflowCLI/Project/ProjectWriter.swift
//
// Pure file-tree writer separated from InitCommand so it's trivially
// testable (no CLI invocation, no Process). InitCommand is a thin wrapper
// that resolves arguments + the embedded driver, then delegates here.

import Foundation

enum ProjectWriterError: Error, Equatable, CustomStringConvertible {
    case targetExists(URL)

    var description: String {
        switch self {
        case .targetExists(let url):
            return "target directory already exists: \(url.path)"
        }
    }
}

enum ProjectWriter {

    /// Creates `<into>/<name>/` and writes the full project tree into it.
    ///
    /// - Parameters:
    ///   - name: project name; used as the directory name and `Package.swift` `name:`.
    ///   - parent: parent directory (the new project becomes a sibling of existing children here).
    ///   - swiflowDep: how the generated `Package.swift` depends on Swiflow — either a local
    ///     `.path(...)` or a versioned URL `.url(..., version:)`.
    ///   - jsDriverSource: contents to write to `swiflow-driver.js`. Pass `EmbeddedDriver.javascriptSource`
    ///     in production; tests pass a stub string.
    /// - Throws: `ProjectWriterError.targetExists` if `<into>/<name>/` already exists, or
    ///   any `FileManager` error encountered while creating directories / writing files.
    static func writeProject(
        name: String,
        into parent: URL,
        swiflowDep: SwiflowDep,
        jsDriverSource: String
    ) throws {
        let fm = FileManager.default
        // Use `isDirectory: false` so the URL we construct (and surface in
        // errors) doesn't sprout a trailing slash if the path already exists
        // on disk as a directory — keeping it equal to the URL a caller would
        // pre-compute via the same plain `appendingPathComponent(name)` call.
        let project = parent.appendingPathComponent(name, isDirectory: false)

        if fm.fileExists(atPath: project.path) {
            throw ProjectWriterError.targetExists(project)
        }

        // Create the directory tree.
        try fm.createDirectory(
            at: project.appendingPathComponent("Sources/App"),
            withIntermediateDirectories: true
        )

        // Write each file.
        try Templates.packageSwift(name: name, swiflowDep: swiflowDep)
            .write(to: project.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try Templates.appSwift(name: name)
            .write(to: project.appendingPathComponent("Sources/App/App.swift"), atomically: true, encoding: .utf8)
        try Templates.indexHTML(name: name)
            .write(to: project.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        try Templates.gitignore()
            .write(to: project.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        try Templates.readme(name: name)
            .write(to: project.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try jsDriverSource
            .write(to: project.appendingPathComponent("swiflow-driver.js"), atomically: true, encoding: .utf8)
    }
}
