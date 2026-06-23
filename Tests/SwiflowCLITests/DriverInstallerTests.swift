// Tests/SwiflowCLITests/DriverInstallerTests.swift
import Foundation
import Testing
@testable import SwiflowCLI

@Suite("DriverInstaller")
struct DriverInstallerTests {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiflow-driverinstaller-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("dev (minified:false) writes readable driver + service worker")
    func devWritesReadable() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try DriverInstaller.install(into: dir, minified: false)
        let driver = try String(contentsOf: dir.appendingPathComponent("swiflow-driver.js"), encoding: .utf8)
        let sw = try String(contentsOf: dir.appendingPathComponent("swiflow-service-worker.js"), encoding: .utf8)
        #expect(driver == EmbeddedDriver.javascriptSource)
        #expect(sw == EmbeddedDriver.serviceWorkerSource)
    }

    @Test("build (minified:true) writes minified driver + service worker")
    func buildWritesMinified() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try DriverInstaller.install(into: dir, minified: true)
        let driver = try String(contentsOf: dir.appendingPathComponent("swiflow-driver.js"), encoding: .utf8)
        #expect(driver == EmbeddedDriver.javascriptSourceMinified)
    }

    @Test("no index.html → region files are not written")
    func plainProjectGetsNoRegionFiles() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try DriverInstaller.install(into: dir, minified: false)
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("swiflow-regions.js").path))
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("swiflow-region-guest.js").path))
    }

    @Test("index.html referencing regions → region pair is written (variant follows minified)")
    func regionProjectGetsRegionFiles() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try "<script type=\"module\" src=\"swiflow-regions.js\"></script>\n"
            .write(to: dir.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        try DriverInstaller.install(into: dir, minified: false)
        let regions = try String(contentsOf: dir.appendingPathComponent("swiflow-regions.js"), encoding: .utf8)
        let guest = try String(contentsOf: dir.appendingPathComponent("swiflow-region-guest.js"), encoding: .utf8)
        #expect(regions == EmbeddedDriver.regionsSource)
        #expect(guest == EmbeddedDriver.guestSdkSource)
    }

    @Test("stampServiceWorker(minified:true) stamps the minified SW variant")
    func stampMinified() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try DriverInstaller.install(into: dir, minified: true)
        try DriverInstaller.stampServiceWorker(into: dir, buildTag: "deadbeefcafe", minified: true)
        let sw = try String(contentsOf: dir.appendingPathComponent("swiflow-service-worker.js"), encoding: .utf8)
        #expect(sw.contains("deadbeefcafe"))
        #expect(!sw.contains("__SWIFLOW_BUILD_TAG__"))
    }

    @Test("the embedded service worker source carries the placeholder for stamping")
    func embeddedServiceWorkerCarriesThePlaceholder() {
        #expect(EmbeddedDriver.serviceWorkerSource.contains("__SWIFLOW_BUILD_TAG__"),
                "the repo/template copy must keep the placeholder for stamping")
    }
}
