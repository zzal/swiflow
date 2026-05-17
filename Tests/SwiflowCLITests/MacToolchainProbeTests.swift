// Tests/SwiflowCLITests/MacToolchainProbeTests.swift
import Foundation
import Testing
@testable import SwiflowCLI

@Suite("MacToolchainProbe")
struct MacToolchainProbeTests {

    @Test("Reads CFBundleIdentifier from a real Info.plist file")
    func readsBundleIdentifier() throws {
        // Create a minimal Info.plist with a fake bundle ID in a temp dir.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("mac-toolchain-probe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let plistURL = tmp.appendingPathComponent("Info.plist")
        let plist: [String: Any] = ["CFBundleIdentifier": "org.swift.6320250501"]
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try data.write(to: plistURL)

        let id = MacToolchainProbe.bundleIdentifier(atInfoPlist: plistURL)
        #expect(id == "org.swift.6320250501")
    }

    @Test("Returns nil for a missing Info.plist")
    func missingPlist() {
        let missing = URL(fileURLWithPath: "/nonexistent/path/Info.plist")
        #expect(MacToolchainProbe.bundleIdentifier(atInfoPlist: missing) == nil)
    }

    @Test("Returns nil for an Info.plist without CFBundleIdentifier")
    func plistWithoutBundleID() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("mac-toolchain-probe-empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let plistURL = tmp.appendingPathComponent("Info.plist")
        let plist: [String: Any] = ["SomeOtherKey": "value"]
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try data.write(to: plistURL)

        #expect(MacToolchainProbe.bundleIdentifier(atInfoPlist: plistURL) == nil)
    }
}
