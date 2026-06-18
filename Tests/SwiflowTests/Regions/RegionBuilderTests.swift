// Tests/SwiflowTests/Regions/RegionBuilderTests.swift
import Testing
@testable import Swiflow

private struct P: Encodable { var x: Int }
private struct E: RegionEvent { let k: String }
private enum G: RegionGuest {
    typealias Props = P; typealias Event = E
    static let source = "regions/g.wasm"
}

@MainActor
@Suite("Region builder integration")
struct RegionBuilderTests {
    @Test("a RegionView can sit inside a div { } body and lowers to a child element")
    func regionInBody() {
        let tree = div {
            region(G.self, key: "k", props: P(x: 1))
        }
        guard case .element(let outer) = tree,
              case .element(let child)? = outer.children.first else {
            Issue.record("expected div with one element child"); return
        }
        #expect(child.tag == "sf-region")
        #expect(child.key == "k")
    }
}
