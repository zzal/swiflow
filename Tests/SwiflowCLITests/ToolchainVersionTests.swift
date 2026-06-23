// Tests/SwiflowCLITests/ToolchainVersionTests.swift
import Testing
@testable import SwiflowCLI

@Suite("ToolchainVersion")
struct ToolchainVersionTests {

    // MARK: compilerVersion

    @Test("Parses the macOS `swift --version` line")
    func compilerMac() {
        let line = "Apple Swift version 6.3.2 (swiftlang-6.3.2.1.108 clang-2100.1.1.101)"
        #expect(ToolchainVersion.compilerVersion(fromVersionLine: line) == "6.3.2")
    }

    @Test("Parses the Linux `swift --version` line")
    func compilerLinux() {
        let line = "Swift version 6.3.2 (swift-6.3.2-RELEASE)"
        #expect(ToolchainVersion.compilerVersion(fromVersionLine: line) == "6.3.2")
    }

    @Test("Returns nil when the line has no recognizable version")
    func compilerUnparseable() {
        #expect(ToolchainVersion.compilerVersion(fromVersionLine: "some unrelated output") == nil)
    }

    // MARK: sdkVersion

    @Test("Parses a patch-versioned SDK id")
    func sdkPatch() {
        #expect(ToolchainVersion.sdkVersion(fromID: "swift-6.3.2-RELEASE_wasm") == "6.3.2")
    }

    @Test("Parses a minor-only SDK id")
    func sdkMinor() {
        #expect(ToolchainVersion.sdkVersion(fromID: "swift-6.3-RELEASE_wasm") == "6.3")
    }

    @Test("The embedded variant still parses its version")
    func sdkEmbedded() {
        #expect(ToolchainVersion.sdkVersion(fromID: "swift-6.3.2-RELEASE_wasm-embedded") == "6.3.2")
    }

    @Test("Development snapshots have no semver → nil (not flagged)")
    func sdkSnapshot() {
        #expect(ToolchainVersion.sdkVersion(fromID: "swift-DEVELOPMENT-SNAPSHOT-2026-01-01-a_wasm") == nil)
    }

    // MARK: versionsMatch

    @Test("6.3 and 6.3.2 are a mismatch (the bug this guards)")
    func mismatchMinorVsPatch() {
        #expect(ToolchainVersion.versionsMatch("6.3.2", "6.3") == false)
    }

    @Test("Identical patch versions match")
    func matchExact() {
        #expect(ToolchainVersion.versionsMatch("6.3.2", "6.3.2") == true)
    }

    @Test("Zero-padding: 6.3 equals 6.3.0")
    func matchZeroPadded() {
        #expect(ToolchainVersion.versionsMatch("6.3", "6.3.0") == true)
    }
}
