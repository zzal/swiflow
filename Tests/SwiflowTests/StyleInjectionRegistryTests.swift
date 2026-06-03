// Tests/SwiflowTests/StyleInjectionRegistryTests.swift
import Testing
import Swiflow

@Suite("StyleInjectionRegistry", .serialized)
@MainActor
struct StyleInjectionRegistryTests {
    @Test func emitsOncePerID() {
        StyleInjectionRegistry.reset()
        var emitted: [(String, String)] = []
        StyleInjectionRegistry.emit = { id, css in emitted.append((id, css)) }
        defer { StyleInjectionRegistry.emit = nil }

        StyleInjectionRegistry.injectOnce(id: "a") { "x{}" }
        StyleInjectionRegistry.injectOnce(id: "a") { "x{}" }   // guarded — no second emit
        #expect(emitted.count == 1)
        #expect(emitted.first?.0 == "a")
        #expect(emitted.first?.1 == "x{}")
    }

    @Test func cssClosureNotEvaluatedWhenGuarded() {
        StyleInjectionRegistry.reset()
        StyleInjectionRegistry.emit = { _, _ in }
        defer { StyleInjectionRegistry.emit = nil }
        var builds = 0
        StyleInjectionRegistry.injectOnce(id: "b") { builds += 1; return "y{}" }
        StyleInjectionRegistry.injectOnce(id: "b") { builds += 1; return "y{}" }
        #expect(builds == 1)   // second call short-circuits before building css
    }

    @Test func resetReArms() {
        StyleInjectionRegistry.reset()
        var count = 0
        StyleInjectionRegistry.emit = { _, _ in count += 1 }
        defer { StyleInjectionRegistry.emit = nil }
        StyleInjectionRegistry.injectOnce(id: "c") { "z{}" }
        StyleInjectionRegistry.reset() // clears injectedIDs but leaves emit intact
        StyleInjectionRegistry.injectOnce(id: "c") { "z{}" }
        #expect(count == 2)
    }

    @Test func injectOnceReturnsWhetherItEmitted() {
        StyleInjectionRegistry.reset()
        StyleInjectionRegistry.emit = { _, _ in }
        defer { StyleInjectionRegistry.emit = nil }
        #expect(StyleInjectionRegistry.injectOnce(id: "d") { "" } == true)
        #expect(StyleInjectionRegistry.injectOnce(id: "d") { "" } == false)
    }
}
