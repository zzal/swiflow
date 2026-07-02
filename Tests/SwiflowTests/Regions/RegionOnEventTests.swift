// Tests/SwiflowTests/Regions/RegionOnEventTests.swift
import Testing
@testable import Swiflow

private struct SceneProps: Encodable { var count: Int }
private struct SceneEvent: RegionEvent, Equatable { let kind: String; let id: Int }
private enum Scene: RegionGuest {
    typealias Props = SceneProps; typealias Event = SceneEvent
    static let source = "regions/scene.wasm"
}

/// Returns a preset typed value, and records the JSON it was handed.
private final class RecordingDecoder: RegionEventDecoding {
    let event: SceneEvent
    init(_ e: SceneEvent) { self.event = e }
    func decode<E: Decodable>(_ type: E.Type, from json: String) throws -> E {
        guard let typed = event as? E else { throw RegionError(code: "x", message: json) }
        return typed
    }
}

@MainActor
@Suite("Region .onEvent")
struct RegionOnEventTests {
    @Test(".onEvent registers an sf:event handler that decodes detail into the typed closure")
    func onEventDecodes() {
        let registry = HandlerRegistry()
        HandlerAmbient.current = registry
        RegionDecoder.current = RecordingDecoder(SceneEvent(kind: "select", id: 9))
        defer { HandlerAmbient.current = nil; RegionDecoder.current = nil }

        var received: SceneEvent?
        let view = region(Scene.self, key: "hero", props: SceneProps(count: 1))
            .onEvent { e in received = e }

        guard case .element(let data) = view.asVNode(),
              let handler = data.handlers["sf:event"] else {
            Issue.record("expected an sf:event handler"); return
        }
        registry.dispatch(id: handler.id, event: EventInfo(type: "sf:event", detail: #"{"kind":"select","id":9}"#))
        #expect(received == SceneEvent(kind: "select", id: 9))
    }

    @Test("event is dropped when detail is nil, with a diagnostic")
    func dropsWhenDetailNil() {
        let registry = HandlerRegistry()
        HandlerAmbient.current = registry
        RegionDecoder.current = RecordingDecoder(SceneEvent(kind: "select", id: 9))
        defer { HandlerAmbient.current = nil; RegionDecoder.current = nil }

        var fired = false
        let view = region(Scene.self, key: "hero", props: SceneProps(count: 1))
            .onEvent { _ in fired = true }
        guard case .element(let data) = view.asVNode(), let handler = data.handlers["sf:event"] else {
            Issue.record("expected an sf:event handler"); return
        }

        var captured: [String] = []
        let prior = _swiflowDiagnosticOverride
        _swiflowDiagnosticOverride = { captured.append($0) }
        defer { _swiflowDiagnosticOverride = prior }

        registry.dispatch(id: handler.id, event: EventInfo(type: "sf:event", detail: nil))
        #expect(fired == false)
        #expect(captured.contains { $0.contains("no detail payload") })
    }

    @Test("event is dropped when no decoder is installed, with a diagnostic")
    func dropsWhenNoDecoder() {
        let registry = HandlerRegistry()
        HandlerAmbient.current = registry
        RegionDecoder.current = nil
        defer { HandlerAmbient.current = nil }

        var fired = false
        let view = region(Scene.self, key: "hero", props: SceneProps(count: 1))
            .onEvent { _ in fired = true }
        guard case .element(let data) = view.asVNode(), let handler = data.handlers["sf:event"] else {
            Issue.record("expected an sf:event handler"); return
        }

        var captured: [String] = []
        let prior = _swiflowDiagnosticOverride
        _swiflowDiagnosticOverride = { captured.append($0) }
        defer { _swiflowDiagnosticOverride = prior }

        registry.dispatch(id: handler.id, event: EventInfo(type: "sf:event", detail: #"{"kind":"select","id":9}"#))
        #expect(fired == false)
        #expect(captured.contains { $0.contains("no RegionDecoder is installed") })
    }

    @Test("event is dropped when decode fails, with a diagnostic")
    func dropsWhenDecodeFails() {
        let registry = HandlerRegistry()
        HandlerAmbient.current = registry
        struct ThrowingDecoder: RegionEventDecoding {
            func decode<E: Decodable>(_ type: E.Type, from json: String) throws -> E {
                throw RegionError(code: "bad", message: "nope")
            }
        }
        RegionDecoder.current = ThrowingDecoder()
        defer { HandlerAmbient.current = nil; RegionDecoder.current = nil }

        var fired = false
        let view = region(Scene.self, key: "hero", props: SceneProps(count: 1))
            .onEvent { _ in fired = true }
        guard case .element(let data) = view.asVNode(), let handler = data.handlers["sf:event"] else {
            Issue.record("expected an sf:event handler"); return
        }

        var captured: [String] = []
        let prior = _swiflowDiagnosticOverride
        _swiflowDiagnosticOverride = { captured.append($0) }
        defer { _swiflowDiagnosticOverride = prior }

        registry.dispatch(id: handler.id, event: EventInfo(type: "sf:event", detail: #"{"kind":"select","id":9}"#))
        #expect(fired == false)
        #expect(captured.contains { $0.contains("decode failed") })
    }
}
