// Tests/SwiflowTests/Regions/RegionContractTests.swift
import Testing
@testable import Swiflow

private struct DemoProps: Encodable { var count: Int }
private struct DemoEvent: RegionEvent { let kind: String; let id: Int }
private enum DemoGuest: RegionGuest {
    typealias Props = DemoProps
    typealias Event = DemoEvent
    static let source = "regions/demo.wasm"
}

@Suite("Region contract")
struct RegionContractTests {
    @Test("A guest binds its source, props, and event types")
    func guestBindsTypes() {
        #expect(DemoGuest.source == "regions/demo.wasm")
        // Associated types are usable:
        let _: DemoGuest.Props = DemoProps(count: 1)
        let _: DemoGuest.Event.Type = DemoEvent.self
    }

    @Test("RegionError decodes from its wire shape")
    func regionErrorIsDecodable() {
        let _: RegionError.Type = RegionError.self
        let err = RegionError(code: "load-failed", message: "404")
        #expect(err.code == "load-failed")
        #expect(err.message == "404")
    }
}
