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
    ///   - jsServiceWorkerSource: contents to write to `swiflow-sw.js`. Pass
    ///     `EmbeddedDriver.serviceWorkerSource` in production; tests pass a stub string.
    ///   - _testFailDuringWrites: test-only hook; when `true`, throws immediately after
    ///     `createDirectory` so the cleanup path is exercised deterministically. Production
    ///     callers omit this parameter (it defaults to `false`).
    /// - Throws: `ProjectWriterError.targetExists` if `<into>/<name>/` already exists, or
    ///   any `FileManager` error encountered while creating directories / writing files.
    ///   If a write fails after the target dir is created, the target dir is removed
    ///   before the error is re-thrown — the user can re-run `swiflow init` without
    ///   first manually deleting the partial output.
    static func writeProject(
        name: String,
        into parent: URL,
        swiflowDep: SwiflowDep,
        jsDriverSource: String,
        jsServiceWorkerSource: String,
        _testFailDuringWrites: Bool = false
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

        // Write files. Any error during this phase triggers cleanup of the
        // half-populated target dir so the user can re-run `swiflow init`
        // without first manually removing the partial output.
        do {
            if _testFailDuringWrites {
                // Simulate a write failure by throwing the same error shape
                // FileManager would throw if disk-full / permission-denied
                // interrupted one of the .write() calls below. Using a Cocoa
                // error (not ProjectWriterError) keeps the semantics honest:
                // targetExists means "dir was there before we started" and
                // already fired earlier at the precondition guard.
                throw CocoaError(.fileWriteUnknown)
            }
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
            try jsServiceWorkerSource
                .write(to: project.appendingPathComponent("swiflow-sw.js"), atomically: true, encoding: .utf8)
        } catch {
            // Best-effort cleanup; ignore removal errors so we still surface
            // the original failure to the caller.
            try? fm.removeItem(at: project)
            throw error
        }
    }
}
