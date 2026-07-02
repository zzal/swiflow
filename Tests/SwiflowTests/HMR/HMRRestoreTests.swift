import Testing
@testable import Swiflow

@MainActor @Component
private final class HMRR_Counter {
    @State var count: Int = 0
    @State var label: String = "initial"
    var body: VNode { .text("") }
}

@MainActor
@Suite("HMR restore applier")
struct HMRRestoreTests {

    @Test("restore overwrites matching @State fields")
    func restoreOverwritesMatchingFields() {
        let snap = ComponentSnapshot(
            path: "",
            typeName: String(reflecting: HMRR_Counter.self),
            key: nil,
            state: ["count": 42, "label": "restored"]
        )
        let index = HMRWalker.indexSnapshots([snap])

        let fresh = HMRR_Counter()
        let anyC = AnyComponent(fresh)
        applyHMRRestore(index: index, to: anyC, at: "", key: nil)

        #expect(fresh.count == 42)
        #expect(fresh.label == "restored")
    }

    @Test("restore is a no-op when no matching snapshot exists")
    func restoreNoMatch() {
        let snap = ComponentSnapshot(
            path: "1.0",
            typeName: String(reflecting: HMRR_Counter.self),
            key: nil,
            state: ["count": 99]
        )
        let index = HMRWalker.indexSnapshots([snap])

        let fresh = HMRR_Counter()
        let anyC = AnyComponent(fresh)
        applyHMRRestore(index: index, to: anyC, at: "", key: nil)

        #expect(fresh.count == 0)
        #expect(fresh.label == "initial")
    }

    @Test("restore matches keyed components by key, ignores unkeyed snapshot at same path")
    func restoreKeyedComponent() {
        // Two components at the same path but different keys. Without the
        // key in the lookup, both would resolve against the same nil-key
        // bucket and one would silently receive the wrong state.
        let snapA = ComponentSnapshot(
            path: "0",
            typeName: String(reflecting: HMRR_Counter.self),
            key: "a",
            state: ["count": 1, "label": "alice"]
        )
        let snapB = ComponentSnapshot(
            path: "0",
            typeName: String(reflecting: HMRR_Counter.self),
            key: "b",
            state: ["count": 2, "label": "bob"]
        )
        let index = HMRWalker.indexSnapshots([snapA, snapB])

        let freshA = HMRR_Counter()
        applyHMRRestore(index: index, to: AnyComponent(freshA), at: "0", key: "a")
        #expect(freshA.count == 1)
        #expect(freshA.label == "alice")

        let freshB = HMRR_Counter()
        applyHMRRestore(index: index, to: AnyComponent(freshB), at: "0", key: "b")
        #expect(freshB.count == 2)
        #expect(freshB.label == "bob")

        // An unkeyed lookup at the same path finds nothing — no bucket
        // for key: nil exists when all snapshots at that path carry keys.
        let freshUnkeyed = HMRR_Counter()
        applyHMRRestore(index: index, to: AnyComponent(freshUnkeyed), at: "0", key: nil)
        #expect(freshUnkeyed.count == 0)
        #expect(freshUnkeyed.label == "initial")
    }

    @Test("restore skips fields missing from the snapshot")
    func restorePartialFieldSet() {
        let snap = ComponentSnapshot(
            path: "",
            typeName: String(reflecting: HMRR_Counter.self),
            key: nil,
            state: ["count": 7]  // no `label`
        )
        let index = HMRWalker.indexSnapshots([snap])

        let fresh = HMRR_Counter()
        applyHMRRestore(index: index, to: AnyComponent(fresh), at: "", key: nil)

        #expect(fresh.count == 7)
        #expect(fresh.label == "initial")  // unchanged
    }
}
