import Testing
@testable import Swiflow

@MainActor
@Suite("HMR round-trip")
struct HMRRoundTripTests {

    final class Demo: Component {
        @State var s: String = ""
        @State var i: Int = 0
        @State var d: Double = 0
        @State var b: Bool = false
        @State var os: String? = nil
        var body: VNode { .text("") }
    }

    @Test("snapshot → index → applyRestore preserves all supported primitives")
    func roundTripAllPrimitives() {
        let original = Demo()
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

        let fresh = Demo()
        HMRWalker.applyRestore(index: index, to: AnyComponent(fresh), at: "")

        #expect(fresh.s == "hello")
        #expect(fresh.i == 42)
        #expect(fresh.d == 3.14)
        #expect(fresh.b == true)
        #expect(fresh.os == "optional")
    }

    @Test("round-trip preserves nil Optional<String>")
    func roundTripNilOptional() {
        let original = Demo()
        original.s = "x"
        original.os = nil

        let tree = MountNode(
            handle: 1,
            vnode: .text(""),
            component: AnyComponent(original)
        )
        let snaps = HMRWalker.snapshot(from: tree)
        let index = HMRWalker.indexSnapshots(snaps)

        let fresh = Demo()
        fresh.os = "before-restore"
        HMRWalker.applyRestore(index: index, to: AnyComponent(fresh), at: "")

        #expect(fresh.s == "x")
        #expect(fresh.os == nil)
    }
}
