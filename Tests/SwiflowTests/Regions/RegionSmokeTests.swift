// Tests/SwiflowTests/Regions/RegionSmokeTests.swift
import Testing
@testable import Swiflow

private struct SceneProps: Encodable { var count: Int; var hue: Double }
private struct SceneEvent: RegionEvent { enum Kind: String, Decodable { case select, hover }; let kind: Kind; let id: Int }
private enum Scene: RegionGuest {
    typealias Props = SceneProps; typealias Event = SceneEvent
    static let source = "regions/scene.wasm"
}

@MainActor
@Suite("Region smoke")
struct RegionSmokeTests {
    @Test("the canonical typed call site composes and lowers to one sf-region child")
    func canonical() {
        let registry = HandlerRegistry()
        HandlerAmbient.current = registry
        defer { HandlerAmbient.current = nil }

        var selected = 0
        var fellBack = false
        let tree = div {
            region(Scene.self, key: "hero", props: SceneProps(count: 3, hue: 0.5))
                .onEvent { e in selected = e.id }     // e: SceneEvent inferred
                .onError { _ in fellBack = true }
                .fill()
        }
        guard case .element(let outer) = tree,
              case .element(let child)? = outer.children.first else {
            Issue.record("expected one sf-region child"); return
        }
        #expect(child.tag == "sf-region")
        #expect(child.handlers["sf:event"] != nil)
        #expect(child.handlers["sf:error"] != nil)
        #expect(child.style["width"] == "100%")
        _ = (selected, fellBack) // silence unused warnings; behavior covered in Tasks 8–9
    }
}
