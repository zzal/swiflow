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

    @Test("writes swiflow-driver.js and swiflow-sw.js verbatim from EmbeddedDriver")
    func writesBothFiles() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try DriverInstaller.install(into: dir)

        let driver = try String(contentsOf: dir.appendingPathComponent("swiflow-driver.js"), encoding: .utf8)
        let sw = try String(contentsOf: dir.appendingPathComponent("swiflow-sw.js"), encoding: .utf8)
        #expect(driver == EmbeddedDriver.javascriptSource)
        #expect(sw == EmbeddedDriver.serviceWorkerSource)
    }

    @Test("overwrites a stale existing driver so the served copy matches the CLI")
    func overwritesStale() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let driverURL = dir.appendingPathComponent("swiflow-driver.js")
        try "// stale driver\n".write(to: driverURL, atomically: true, encoding: .utf8)

        try DriverInstaller.install(into: dir)

        let driver = try String(contentsOf: driverURL, encoding: .utf8)
        #expect(driver == EmbeddedDriver.javascriptSource)
        #expect(!driver.contains("// stale driver"))
    }
}
