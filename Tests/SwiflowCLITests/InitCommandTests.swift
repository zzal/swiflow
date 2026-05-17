// Tests/SwiflowCLITests/InitCommandTests.swift
import Foundation
import Testing
@testable import SwiflowCLI

@Suite("InitCommand")
struct InitCommandTests {
    @Test("Init creates the expected file tree")
    func createsFileTree() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        try ProjectWriter.writeProject(
            name: "Demo",
            into: tmp,
            swiflowSource: "../..",
            jsDriverSource: "// fake driver\n"
        )

        let project = tmp.appendingPathComponent("Demo")
        let fm = FileManager.default

        #expect(fm.fileExists(atPath: project.path))
        #expect(fm.fileExists(atPath: project.appendingPathComponent("Package.swift").path))
        #expect(fm.fileExists(atPath: project.appendingPathComponent("Sources/App/App.swift").path))
        #expect(fm.fileExists(atPath: project.appendingPathComponent("index.html").path))
        #expect(fm.fileExists(atPath: project.appendingPathComponent("swiflow-driver.js").path))
        #expect(fm.fileExists(atPath: project.appendingPathComponent(".gitignore").path))
        #expect(fm.fileExists(atPath: project.appendingPathComponent("README.md").path))
    }

    @Test("Init writes the embedded driver verbatim to swiflow-driver.js")
    func writesDriverVerbatim() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let driver = "// custom driver payload\nconsole.log('hi');\n"
        try ProjectWriter.writeProject(
            name: "Demo",
            into: tmp,
            swiflowSource: "../..",
            jsDriverSource: driver
        )

        let url = tmp.appendingPathComponent("Demo/swiflow-driver.js")
        let onDisk = try String(contentsOf: url, encoding: .utf8)
        #expect(onDisk == driver)
    }

    @Test("Init refuses to overwrite an existing directory")
    func refusesOverwrite() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Pre-create the target so the writer collides.
        let collision = tmp.appendingPathComponent("Demo")
        try FileManager.default.createDirectory(at: collision, withIntermediateDirectories: true)

        #expect(throws: ProjectWriterError.targetExists(collision)) {
            try ProjectWriter.writeProject(
                name: "Demo",
                into: tmp,
                swiflowSource: "../..",
                jsDriverSource: "// driver\n"
            )
        }
    }

    @Test("Init applies the swiflow-source argument to the generated Package.swift")
    func threadsSwiflowSource() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        try ProjectWriter.writeProject(
            name: "Demo",
            into: tmp,
            swiflowSource: "/abs/path/to/swiflow",
            jsDriverSource: "// driver\n"
        )

        let pkg = try String(
            contentsOf: tmp.appendingPathComponent("Demo/Package.swift"),
            encoding: .utf8
        )
        #expect(pkg.contains(#".package(path: "/abs/path/to/swiflow")"#))
    }

    // MARK: - Helpers

    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiflow-init-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
