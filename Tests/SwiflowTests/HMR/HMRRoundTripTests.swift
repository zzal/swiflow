import Testing
@testable import Swiflow

@MainActor @Component
private final class HMRRT_Demo {
    @State var s: String = ""
    @State var i: Int = 0
    @State var d: Double = 0
    @State var b: Bool = false
    @State var os: String? = nil
    var body: VNode { .text("") }
}

@MainActor @Component
private final class HMRRT_Prices {
    @State var price: Double = 0.0
    @State var optPrice: Double? = nil
    var body: VNode { .text("") }
}

@MainActor @Component
private final class HMRRT_Nullable {
    @State var label: String? = nil
    @State var name: String = "keep"
    var body: VNode { .text("") }
}

@MainActor
@Suite("HMR round-trip")
struct HMRRoundTripTests {

    @Test("snapshot → index → applyRestore preserves all supported primitives")
    func roundTripAllPrimitives() {
        let original = HMRRT_Demo()
        original.s = "hello"
        original.i = 42
        original.d = 3.14
        original.b = true
        original.os = "optional"

        let tree = MountNode(
            handle: 1,
            vnode: .text(""),
            component: AnyComponent(original)
        )
        let snaps = HMRWalker.snapshot(from: tree)
        let index = HMRWalker.indexSnapshots(snaps)

        let fresh = HMRRT_Demo()
        HMRWalker.applyRestore(index: index, to: AnyComponent(fresh), at: "", key: nil)

        #expect(fresh.s == "hello")
        #expect(fresh.i == 42)
        #expect(fresh.d == 3.14)
        #expect(fresh.b == true)
        #expect(fresh.os == "optional")
    }

    @Test("_hmrRestore coerces Int → Double for integral values from JS bridge")
    func intToDoubleCoercion() {
        // Simulates the JS bridge path: decodeStateMap stores `42.0` as
        // `Int(42)` (all integral JS numbers are Int-biased). Without the
        // coercion added in the Blocker 2 fix, `Int(42) as? Double` is nil
        // and the field silently reverts to its declared initial (0.0).
        let snap = ComponentSnapshot(
            path: "",
            typeName: String(reflecting: HMRRT_Prices.self),
            key: nil,
            state: [
                "price": Int(42),       // would arrive as Int from decodeStateMap
                "optPrice": Int(7),     // Double? receiving Int
            ]
        )
        let index = HMRWalker.indexSnapshots([snap])
        let fresh = HMRRT_Prices()
        HMRWalker.applyRestore(index: index, to: AnyComponent(fresh), at: "", key: nil)

        #expect(fresh.price == 42.0)
        #expect(fresh.optPrice == 7.0)
    }

    @Test("applyRestore restores nil Optional via HMRNilSentinel (JS bridge path)")
    func nilSentinelRestoresOptionalToNone() {
        // Simulates the JS bridge path: decodeStateMap decodes JS `null` as
        // HMRNilSentinel. Without the Blocker 3 fix, the sentinel is routed
        // through _hmrRestore which can't match it to String?, so the field
        // is silently left at the declared initial ("before-restore").
        let snap = ComponentSnapshot(
            path: "",
            typeName: String(reflecting: HMRRT_Nullable.self),
            key: nil,
            state: [
                "label": HMRNilSentinel(),  // JS null → sentinel
                "name": "restored",
            ]
        )
        let index = HMRWalker.indexSnapshots([snap])
        let fresh = HMRRT_Nullable()
        fresh.label = "before-restore"
        HMRWalker.applyRestore(index: index, to: AnyComponent(fresh), at: "", key: nil)

        #expect(fresh.label == nil)      // sentinel correctly restored to .none
        #expect(fresh.name == "restored")
    }

    @Test("round-trip preserves nil Optional<String>")
    func roundTripNilOptional() {
        let original = HMRRT_Demo()
        original.s = "x"
        original.os = nil

        let tree = MountNode(
            handle: 1,
            vnode: .text(""),
            component: AnyComponent(original)
        )
        let snaps = HMRWalker.snapshot(from: tree)
        let index = HMRWalker.indexSnapshots(snaps)

        let fresh = HMRRT_Demo()
        fresh.os = "before-restore"
        HMRWalker.applyRestore(index: index, to: AnyComponent(fresh), at: "", key: nil)

        #expect(fresh.s == "x")
        #expect(fresh.os == nil)
    }
}
