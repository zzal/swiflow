// Tests/SwiflowTests/Regions/RegionInlineTests.swift
import Testing
@testable import Swiflow

private struct ChartProps: Encodable { var bars: Int }
private struct ChartEvent: RegionEvent, Equatable { let bar: Int }

private final class ChartDecoder: RegionEventDecoding {
    func decode<E: Decodable>(_ type: E.Type, from json: String) throws -> E {
        guard let v = ChartEvent(bar: 4) as? E else { throw RegionError(code: "x", message: json) }
        return v
    }
}

@MainActor
@Suite("Region inline form")
struct RegionInlineTests {
    @Test("region(source:key:props:) lowers like the typed form")
    func inlineLowers() {
        let v = region(source: "regions/chart.wasm", key: "c", props: ChartProps(bars: 12))
        guard case .element(let d) = v.asVNode() else { Issue.record("expected element"); return }
        #expect(d.tag == "sf-region")
        #expect(d.attributes["data-source"] == "regions/chart.wasm")
        guard case .string(let json)? = d.properties["sfProps"] else { Issue.record("expected sfProps"); return }
        #expect(json.contains("\"bars\":12"))
    }

    @Test("inline .onEvent requires an annotation but decodes the same way")
    func inlineOnEvent() {
        let registry = HandlerRegistry()
        HandlerAmbient.current = registry
        RegionDecoder.current = ChartDecoder()
        defer { HandlerAmbient.current = nil; RegionDecoder.current = nil }

        var got: ChartEvent?
        let v = region(source: "regions/chart.wasm", key: "c", props: ChartProps(bars: 1))
            .onEvent { (e: ChartEvent) in got = e }
        guard case .element(let d) = v.asVNode(), let h = d.handlers["sf:event"] else {
            Issue.record("expected sf:event handler"); return
        }
        registry.dispatch(id: h.id, event: EventInfo(type: "sf:event", detail: "{}"))
        #expect(got == ChartEvent(bar: 4))
    }
}
