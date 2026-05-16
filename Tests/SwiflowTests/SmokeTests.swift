// Tests/SwiflowTests/SmokeTests.swift
import Testing
@testable import Swiflow

@Suite("Smoke")
struct SmokeTests {
    @Test("Module imports cleanly")
    func moduleImports() {
        _ = Swiflow.self
    }
}
