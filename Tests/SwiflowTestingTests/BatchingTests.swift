// Tests/SwiflowTestingTests/BatchingTests.swift
//
// Audit VI Wave-2 #4: the batching divergence. RAFScheduler fires ONE
// flush-batch callback per frame; SyncScheduler fired its callback once PER
// dirty component — so an interaction that dirtied two components produced
// two full-root renders in the harness where the browser produces one
// (double onChange fires, double diffs, harness-only). The harness root now
// uses SyncScheduler's batch mode; these tests pin one-render-per-flush.
import Testing
import Swiflow
@testable import SwiflowTesting

@MainActor
private enum BatchProbe {
    static var rootEvals = 0
}

@Component
private final class BatchChild {
    @State var childHits: Int = 0
    let onBump: @MainActor () -> Void
    init(onBump: @escaping @MainActor () -> Void) { self.onBump = onBump }
    var body: VNode {
        button("bump both \(childHits)", .on(.click) {
            self.childHits += 1   // dirties the child…
            self.onBump()         // …and the parent, in the same handler
        })
    }
}

@Component
private final class BatchParent {
    @State var parentHits: Int = 0
    var body: VNode {
        BatchProbe.rootEvals += 1
        return div {
            p("parent \(parentHits)")
            // Keyed embeds need keyed siblings — isolate in a container.
            div { embed("child") { BatchChild(onBump: { self.parentHits += 1 }) } }
        }
    }
}

@MainActor
private enum SoloProbe {
    static var evals = 0
}

@Component
private final class SoloCounter {
    @State var n: Int = 0
    var body: VNode {
        SoloProbe.evals += 1
        return button("n \(n)", .on(.click) { self.n += 1 })
    }
}

@Suite("flush batching — one render per flush, like the browser's rAF tick")
@MainActor
struct BatchingTests {

    @Test("an interaction dirtying TWO components renders the root ONCE")
    func multiDirtyRendersOnce() {
        let h = render(BatchParent())
        BatchProbe.rootEvals = 0

        h.click("button", text: "bump both")

        #expect(BatchProbe.rootEvals == 1,
                "one flush batch → one root render (was one render PER dirty component)")
        #expect(h.find("p")?.text == "parent 1")
        #expect(h.find("button")?.text == "bump both 1")
    }

    @Test("a single-dirty interaction still renders exactly once")
    func singleDirtyRendersOnce() {
        let h = render(SoloCounter())
        SoloProbe.evals = 0

        h.click("button")

        #expect(SoloProbe.evals == 1)
        #expect(h.find("button")?.text == "n 1")
    }
}
