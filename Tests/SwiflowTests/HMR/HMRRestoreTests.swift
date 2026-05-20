import Testing
@testable import Swiflow

@MainActor
@Suite("HMR restore applier")
struct HMRRestoreTests {

    final class Counter: Component {
        @State var count: Int = 0
        @State var label: String = "initial"
        var body: VNode { .text("") }
    }

    @Test("applyRestore overwrites matching @State fields")
    func restoreOverwritesMatchingFields() {
        let snap = ComponentSnapshot(
            path: "",
            typeName: String(reflecting: Counter.self),
            key: nil,
            state: ["count": 42, "label": "restored"]
        )
        let index = HMRWalker.indexSnapshots([snap])

        let fresh = Counter()
        let anyC = AnyComponent(fresh)
        HMRWalker.applyRestore(index: index, to: anyC, at: "")

        #expect(fresh.count == 42)
        #expect(fresh.label == "restored")
    }

    @Test("applyRestore is a no-op when no matching snapshot exists")
    func restoreNoMatch() {
        let snap = ComponentSnapshot(
            path: "1.0",
            typeName: String(reflecting: Counter.self),
            key: nil,
            state: ["count": 99]
        )
        let index = HMRWalker.indexSnapshots([snap])

        let fresh = Counter()
        let anyC = AnyComponent(fresh)
        HMRWalker.applyRestore(index: index, to: anyC, at: "")

        #expect(fresh.count == 0)
        #expect(fresh.label == "initial")
    }

    @Test("applyRestore skips fields missing from the snapshot")
    func restorePartialFieldSet() {
        let snap = ComponentSnapshot(
            path: "",
            typeName: String(reflecting: Counter.self),
            key: nil,
            state: ["count": 7]  // no `label`
        )
        let index = HMRWalker.indexSnapshots([snap])

        let fresh = Counter()
        HMRWalker.applyRestore(index: index, to: AnyComponent(fresh), at: "")

        #expect(fresh.count == 7)
        #expect(fresh.label == "initial")  // unchanged
    }
}
