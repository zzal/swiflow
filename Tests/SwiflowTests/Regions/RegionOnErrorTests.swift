// Tests/SwiflowTests/Regions/RegionOnErrorTests.swift
import Testing
@testable import Swiflow

private struct P: Encodable { var x: Int }
private struct E: RegionEvent { let k: String }
private enum G: RegionGuest {
    typealias Props = P; typealias Event = E
    static let source = "regions/g.wasm"
}

private final class ErrDecoder: RegionEventDecoding {
    let err: RegionError
    init(_ e: RegionError) { self.err = e }
    func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
        guard let typed = err as? T else { throw RegionError(code: "x", message: json) }
        return typed
    }
}

@MainActor
@Suite("Region .onError")
struct RegionOnErrorTests {
    @Test(".onError registers an sf:error handler that decodes RegionError")
    func onErrorDecodes() {
        let registry = HandlerRegistry()
        HandlerAmbient.current = registry
        RegionDecoder.current = ErrDecoder(RegionError(code: "load-failed", message: "404"))
        defer { HandlerAmbient.current = nil; RegionDecoder.current = nil }

        var received: RegionError?
        let view = region(G.self, key: "k", props: P(x: 1)).onError { received = $0 }

        guard case .element(let data) = view.asVNode(),
              let handler = data.handlers["sf:error"] else {
            Issue.record("expected an sf:error handler"); return
        }
        registry.dispatch(id: handler.id, event: EventInfo(type: "sf:error", detail: #"{"code":"load-failed","message":"404"}"#))
        #expect(received == RegionError(code: "load-failed", message: "404"))
    }

    @Test("error is dropped when detail is nil, with a diagnostic")
    func dropsWhenDetailNil() {
        let registry = HandlerRegistry()
        HandlerAmbient.current = registry
        RegionDecoder.current = ErrDecoder(RegionError(code: "load-failed", message: "404"))
        defer { HandlerAmbient.current = nil; RegionDecoder.current = nil }

        var fired = false
        let view = region(G.self, key: "k", props: P(x: 1)).onError { _ in fired = true }
        guard case .element(let data) = view.asVNode(), let handler = data.handlers["sf:error"] else {
            Issue.record("expected an sf:error handler"); return
        }

        var captured: [String] = []
        let prior = _swiflowDiagnosticOverride
        _swiflowDiagnosticOverride = { captured.append($0) }
        defer { _swiflowDiagnosticOverride = prior }

        registry.dispatch(id: handler.id, event: EventInfo(type: "sf:error", detail: nil))
        #expect(fired == false)
        #expect(captured.contains { $0.contains("no detail payload") })
    }

    @Test("error is dropped when no decoder is installed, with a diagnostic")
    func dropsWhenNoDecoder() {
        let registry = HandlerRegistry()
        HandlerAmbient.current = registry
        RegionDecoder.current = nil
        defer { HandlerAmbient.current = nil }

        var fired = false
        let view = region(G.self, key: "k", props: P(x: 1)).onError { _ in fired = true }
        guard case .element(let data) = view.asVNode(), let handler = data.handlers["sf:error"] else {
            Issue.record("expected an sf:error handler"); return
        }

        var captured: [String] = []
        let prior = _swiflowDiagnosticOverride
        _swiflowDiagnosticOverride = { captured.append($0) }
        defer { _swiflowDiagnosticOverride = prior }

        registry.dispatch(id: handler.id, event: EventInfo(type: "sf:error", detail: #"{"code":"load-failed","message":"404"}"#))
        #expect(fired == false)
        #expect(captured.contains { $0.contains("no RegionDecoder is installed") })
    }
}
