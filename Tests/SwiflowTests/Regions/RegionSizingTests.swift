// Tests/SwiflowTests/Regions/RegionSizingTests.swift
import Testing
@testable import Swiflow

private struct P: Encodable { var x: Int }
private struct E: RegionEvent { let k: String }
private enum G: RegionGuest {
    typealias Props = P; typealias Event = E
    static let source = "regions/g.wasm"
}

@MainActor
@Suite("Region sizing")
struct RegionSizingTests {
    private func style(_ v: RegionView<G>) -> [String: String] {
        guard case .element(let d) = v.asVNode() else { return [:] }
        return d.style
    }

    @Test(".fill sets width/height 100%")
    func fill() {
        let s = style(region(G.self, key: "k", props: P(x: 1)).fill())
        #expect(s["width"] == "100%")
        #expect(s["height"] == "100%")
    }

    @Test(".frame sets fixed px")
    func frame() {
        let s = style(region(G.self, key: "k", props: P(x: 1)).frame(width: 640, height: 480))
        #expect(s["width"] == "640px")
        #expect(s["height"] == "480px")
    }

    @Test(".aspectRatio is self-sufficient: aspect-ratio + width 100%")
    func aspect() {
        let s = style(region(G.self, key: "k", props: P(x: 1)).aspectRatio(16, 9))
        #expect(s["aspect-ratio"] == "16 / 9")
        #expect(s["width"] == "100%")
    }
}
