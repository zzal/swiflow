// Tests/SwiflowTests/Reactivity/HMRMultiRootTests.swift
import Testing
@testable import Swiflow

@MainActor @Component
private final class HMRMulti_Counter {
    @State var count: Int = 0
    var body: VNode { .text("") }
}

@MainActor @Component
private final class HMRMulti_Toggle {
    @State var on: Bool = false
    var body: VNode { .text("") }
}

@Suite
@MainActor
struct HMRMultiRootTests {

    @Test func snapshotFromRootsConcatenatesPerRootSnapshots() {
        // Tree A: a single Counter anchor (mirrors HMRSnapshotTests setup).
        let counterA = HMRMulti_Counter()
        counterA.count = 3
        let bodyA = MountNode(handle: 10, vnode: .text(""))
        let treeA = MountNode(
            handle: 11,
            vnode: .component(.init(HMRMulti_Counter.self) { HMRMulti_Counter() }),
            component: AnyComponent(counterA),
            componentBody: bodyA
        )

        // Tree B: a single Toggle anchor at a different root.
        let toggleB = HMRMulti_Toggle()
        toggleB.on = true
        let bodyB = MountNode(handle: 20, vnode: .text(""))
        let treeB = MountNode(
            handle: 21,
            vnode: .component(.init(HMRMulti_Toggle.self) { HMRMulti_Toggle() }),
            component: AnyComponent(toggleB),
            componentBody: bodyB
        )

        let individual = HMRWalker.snapshot(from: treeA) + HMRWalker.snapshot(from: treeB)
        let aggregated = HMRWalker.snapshot(fromRoots: [treeA, treeB])

        #expect(aggregated.count == individual.count)
        #expect(aggregated.map(\.path) == individual.map(\.path))
        #expect(!aggregated.isEmpty)   // both roots contributed
    }

    @Test func snapshotFromEmptyRootsIsEmpty() {
        #expect(HMRWalker.snapshot(fromRoots: []).isEmpty)
    }
}
