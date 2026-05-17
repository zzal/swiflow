// Tests/SwiflowCLITests/SwiftExecutableLocatorTests.swift
import Foundation
import Testing
@testable import SwiflowCLI

@Suite("SwiftExecutableLocator")
struct SwiftExecutableLocatorTests {
    @Test("Picks the first line when stdout has multiple")
    func multipleLines() throws {
        let stub = StubProcessRunner(
            stubbedExitCode: 0,
            stubbedStandardOutput: "/usr/bin/swift\n/opt/local/bin/swift\n"
        )
        let result = try SwiftExecutableLocator.locate(using: stub)
        #expect(result?.path == "/usr/bin/swift")
    }

    @Test("Returns nil on empty output")
    func emptyOutput() throws {
        let stub = StubProcessRunner(stubbedExitCode: 0, stubbedStandardOutput: "")
        let result = try SwiftExecutableLocator.locate(using: stub)
        #expect(result == nil)
    }

    @Test("Returns nil on non-zero exit")
    func nonZeroExit() throws {
        let stub = StubProcessRunner(stubbedExitCode: 1, stubbedStandardOutput: nil)
        let result = try SwiftExecutableLocator.locate(using: stub)
        #expect(result == nil)
    }
}
