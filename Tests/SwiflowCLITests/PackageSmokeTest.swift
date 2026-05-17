// Tests/SwiflowCLITests/PackageSmokeTest.swift
import Testing
@testable import SwiflowCLI

@Suite("Package smoke test")
struct PackageSmokeTest {
    @Test("SwiflowCLI module can be imported and contains the Swiflow root command")
    func canImport() {
        // The root command's name is the CLI binary name.
        #expect(Swiflow.configuration.commandName == "swiflow")
    }
}
