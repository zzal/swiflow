// Sources/SwiflowCLI/Project/ProjectWriter.swift
//
// Pure file-tree writer separated from InitCommand so it's trivially
// testable (no CLI invocation, no Process). InitCommand is a thin wrapper
// that resolves arguments, the chosen template, and the embedded driver,
// then delegates here.

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

    /// Creates `<into>/<name>/` and writes the chosen template's file tree
    /// into it, plus the JS driver + service worker (which come from
    /// EmbeddedDriver, not the template — see EmbeddedTemplates blacklist).
    /// The region pair (`swiflow-regions.js` + `swiflow-region-guest.js`) is
    /// written ONLY when the template's rendered `index.html` references the
    /// regions script (detected via `RuntimeFiles.usesRegions`). Plain
    /// templates do not carry the ~15 KB of unused region JS.
    ///
    /// - Parameters:
    ///   - name: project name; used as the directory name and `{{NAME}}` substitution value.
    ///   - template: the embedded template selected via `--template`.
    ///   - parent: parent directory in which the new project will be created.
    ///   - swiflowDep: how the generated `Package.swift` depends on Swiflow.
    ///   - jsDriverSource / jsServiceWorkerSource / jsRegionsSource / jsGuestSdkSource:
    ///     pass `EmbeddedDriver.javascriptSource` / `.serviceWorkerSource` /
    ///     `.regionsSource` / `.guestSdkSource` in production; tests pass stub strings.
    ///   - _testFailDuringWrites: test-only hook that throws after the target
    ///     directory has been created, so the cleanup path is exercised
    ///     deterministically. Production callers omit it.
    static func writeProject(
        name: String,
        template: EmbeddedTemplates.Template,
        into parent: URL,
        swiflowDep: SwiflowDep,
        jsDriverSource: String,
        jsServiceWorkerSource: String,
        jsRegionsSource: String,
        jsGuestSdkSource: String,
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

        try fm.createDirectory(at: project, withIntermediateDirectories: true)

        do {
            if _testFailDuringWrites {
                throw CocoaError(.fileWriteUnknown)
            }

            // Walk the template's file map. Intermediate directories are
            // created on demand so nested paths (e.g. Sources/App/Pages/Foo.swift
            // in MiniRouter) work without per-template scaffolding logic.
            for (relativePath, raw) in template.files {
                let dest = project.appendingPathComponent(relativePath)
                try fm.createDirectory(
                    at: dest.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                let rendered = Templates.render(raw, name: name, swiflowDep: swiflowDep)
                try rendered.write(to: dest, atomically: true, encoding: .utf8)
            }

            // JS driver and service worker come from EmbeddedDriver, not the
            // template. Keeps canonical js-driver/ bytes in one place.
            try jsDriverSource.write(
                to: project.appendingPathComponent("swiflow-driver.js"),
                atomically: true,
                encoding: .utf8
            )
            try jsServiceWorkerSource.write(
                to: project.appendingPathComponent("swiflow-service-worker.js"),
                atomically: true,
                encoding: .utf8
            )

            // Region runtime is written only when the template's index.html
            // uses it, so plain projects don't carry ~15KB of unused region
            // JS. dev/build re-emit on the same rule (see DriverInstaller).
            let indexHTML = template.files["index.html"]
                .map { Templates.render($0, name: name, swiflowDep: swiflowDep) } ?? ""
            if RuntimeFiles.usesRegions(indexHTML: indexHTML) {
                try jsRegionsSource.write(
                    to: project.appendingPathComponent("swiflow-regions.js"),
                    atomically: true,
                    encoding: .utf8
                )
                try jsGuestSdkSource.write(
                    to: project.appendingPathComponent("swiflow-region-guest.js"),
                    atomically: true,
                    encoding: .utf8
                )
            }
        } catch {
            try? fm.removeItem(at: project)
            throw error
        }
    }
}
