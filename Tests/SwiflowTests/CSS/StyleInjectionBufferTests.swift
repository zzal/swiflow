// Tests/SwiflowTests/CSS/StyleInjectionBufferTests.swift
import Testing
@testable import Swiflow

// Mutates the @MainActor StyleInjectionRegistry global, but every test body
// is synchronous @MainActor — bodies run atomically with no suspension
// points, so tests cannot interleave and no .serialized is needed.
@Suite("StyleInjectionBuffer")
@MainActor
struct StyleInjectionBufferTests {

    @Test("Injections made before the emit sink exists flush when it is installed") func injectionsBeforeTheSinkFlushWhenItArrives() {
        StyleInjectionRegistry.reset()
        StyleInjectionRegistry.emit = nil
        var emitted: [(String, String)] = []

        StyleInjectionRegistry.injectOnce(id: "swiflow-early") { ".x{color:red}" }
        #expect(emitted.isEmpty)

        StyleInjectionRegistry.emit = { id, css in emitted.append((id, css)) }

        #expect(emitted.count == 1)
        #expect(emitted[0].0 == "swiflow-early")
        #expect(emitted[0].1 == ".x{color:red}")

        StyleInjectionRegistry.emit = nil
        StyleInjectionRegistry.reset()
    }

    @Test("A duplicate ID buffered pre-sink still emits only once after the sink arrives") func onceSemanticsSurviveTheBuffer() {
        StyleInjectionRegistry.reset()
        StyleInjectionRegistry.emit = nil
        var emitted: [String] = []

        StyleInjectionRegistry.injectOnce(id: "swiflow-dup") { ".a{}" }
        StyleInjectionRegistry.injectOnce(id: "swiflow-dup") { ".a{}" }
        StyleInjectionRegistry.emit = { id, _ in emitted.append(id) }
        StyleInjectionRegistry.injectOnce(id: "swiflow-dup") { ".a{}" }

        #expect(emitted == ["swiflow-dup"])

        StyleInjectionRegistry.emit = nil
        StyleInjectionRegistry.reset()
    }

    @Test("reset() drops buffered emits instead of replaying them to a later sink") func resetClearsThePendingBuffer() {
        StyleInjectionRegistry.reset()
        StyleInjectionRegistry.emit = nil
        StyleInjectionRegistry.injectOnce(id: "swiflow-stale") { ".s{}" }
        StyleInjectionRegistry.reset()

        var emitted: [String] = []
        StyleInjectionRegistry.emit = { id, _ in emitted.append(id) }
        #expect(emitted.isEmpty, "reset must drop buffered emits, not replay them")

        StyleInjectionRegistry.emit = nil
        StyleInjectionRegistry.reset()
    }
}
