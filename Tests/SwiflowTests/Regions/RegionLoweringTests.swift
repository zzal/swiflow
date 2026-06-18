// Tests/SwiflowTests/Regions/RegionLoweringTests.swift
import Testing
@testable import Swiflow

private struct SceneProps: Encodable { var count: Int; var hue: Double }
private struct SceneEvent: RegionEvent { let kind: String; let id: Int }
private enum Scene: RegionGuest {
    typealias Props = SceneProps
    typealias Event = SceneEvent
    static let source = "regions/scene.wasm"
}

@MainActor
@Suite("Region lowering")
struct RegionLoweringTests {
    @Test("region(_:key:props:) lowers to an <sf-region> element with source attr + encoded props")
    func lowersToElement() {
        let view = region(Scene.self, key: "hero", props: SceneProps(count: 3, hue: 0.5))
        guard case .element(let data) = view.asVNode() else {
            Issue.record("expected .element"); return
        }
        #expect(data.tag == "sf-region")
        #expect(data.key == "hero")
        #expect(data.attributes["data-source"] == "regions/scene.wasm")
        // Props are encoded to a JSON string property the diff can compare:
        guard case .string(let json)? = data.properties["sfProps"] else {
            Issue.record("expected sfProps string property"); return
        }
        #expect(json.contains("\"count\":3"))
        #expect(json.contains("\"hue\":0.5"))
    }
}
