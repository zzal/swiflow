// Tests/SwiflowCLITests/ProjectWriterTests.swift
import Foundation
import Testing
@testable import SwiflowCLI

@Suite("ProjectWriter region emission")
struct ProjectWriterRegionTests {
    private func tmp() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("swiflow-pw-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    // EdgeCases has no swiflow-regions.js in its index.html → plain template.
    @Test("a plain template scaffolds no region JS")
    func plainTemplateNoRegions() throws {
        let parent = try tmp()
        defer { try? FileManager.default.removeItem(at: parent) }
        let tpl = try #require(EmbeddedTemplates.lookup("EdgeCases"))
        try ProjectWriter.writeProject(
            name: "Plain", template: tpl, into: parent, swiflowDep: .path("../.."),
            jsDriverSource: "D", jsServiceWorkerSource: "S",
            jsRegionsSource: "R", jsGuestSdkSource: "G"
        )
        let proj = parent.appendingPathComponent("Plain")
        #expect(!FileManager.default.fileExists(atPath: proj.appendingPathComponent("swiflow-regions.js").path))
        #expect(!FileManager.default.fileExists(atPath: proj.appendingPathComponent("swiflow-region-guest.js").path))
    }

    // HelloWorld's index.html carries the regions script → region template.
    @Test("a region template scaffolds the region JS pair")
    func regionTemplateWritesRegions() throws {
        let parent = try tmp()
        defer { try? FileManager.default.removeItem(at: parent) }
        let tpl = try #require(EmbeddedTemplates.lookup("HelloWorld"))
        try ProjectWriter.writeProject(
            name: "Reg", template: tpl, into: parent, swiflowDep: .path("../.."),
            jsDriverSource: "D", jsServiceWorkerSource: "S",
            jsRegionsSource: "R", jsGuestSdkSource: "G"
        )
        let proj = parent.appendingPathComponent("Reg")
        #expect(try String(contentsOf: proj.appendingPathComponent("swiflow-regions.js"), encoding: .utf8) == "R")
        #expect(try String(contentsOf: proj.appendingPathComponent("swiflow-region-guest.js"), encoding: .utf8) == "G")
    }

    // A hand-crafted stub template with regions in its index.html must also
    // trigger region-file emission (covers the predicate path independent of
    // whatever EmbeddedTemplates ships).
    @Test("a stub template with regions in index.html scaffolds the region JS pair")
    func stubRegionTemplateWritesRegions() throws {
        let parent = try tmp()
        defer { try? FileManager.default.removeItem(at: parent) }
        // Minimal template: index.html references swiflow-regions.js.
        let tpl = EmbeddedTemplates.Template(
            name: "RegionStub",
            files: [
                "index.html": "<script type=\"module\" src=\"swiflow-regions.js\"></script>\n",
                "Package.swift": "// {{SWIFLOW_DEP}}\n",
            ]
        )
        try ProjectWriter.writeProject(
            name: "Reg", template: tpl, into: parent, swiflowDep: .path("../.."),
            jsDriverSource: "D", jsServiceWorkerSource: "S",
            jsRegionsSource: "R", jsGuestSdkSource: "G"
        )
        let proj = parent.appendingPathComponent("Reg")
        #expect(try String(contentsOf: proj.appendingPathComponent("swiflow-regions.js"), encoding: .utf8) == "R")
        #expect(try String(contentsOf: proj.appendingPathComponent("swiflow-region-guest.js"), encoding: .utf8) == "G")
    }

    // A stub template with NO regions must not emit region files.
    @Test("a stub template without regions in index.html scaffolds no region JS")
    func stubPlainTemplateNoRegions() throws {
        let parent = try tmp()
        defer { try? FileManager.default.removeItem(at: parent) }
        let tpl = EmbeddedTemplates.Template(
            name: "PlainStub",
            files: [
                "index.html": "<script src=\"swiflow-driver.js\"></script>\n",
                "Package.swift": "// {{SWIFLOW_DEP}}\n",
            ]
        )
        try ProjectWriter.writeProject(
            name: "Plain", template: tpl, into: parent, swiflowDep: .path("../.."),
            jsDriverSource: "D", jsServiceWorkerSource: "S",
            jsRegionsSource: "R", jsGuestSdkSource: "G"
        )
        let proj = parent.appendingPathComponent("Plain")
        #expect(!FileManager.default.fileExists(atPath: proj.appendingPathComponent("swiflow-regions.js").path))
        #expect(!FileManager.default.fileExists(atPath: proj.appendingPathComponent("swiflow-region-guest.js").path))
    }
}
