import Testing
@testable import Swiflow

@MainActor
private final class Leaf: Component {
    let label: String
    init(_ label: String) { self.label = label }
    var body: VNode { .text(label) }
}

@MainActor
private final class Recorder: RenderObserver {
    var willCount = 0
    var didCount = 0
    var unmounts = 0
    func willEvaluate(owner: AnyComponent, scheduler: (any Scheduler)?) { willCount += 1 }
    func didEvaluate() { didCount += 1 }
    func componentDidUnmount(_ owner: AnyComponent) { unmounts += 1 }
}

@Suite("RenderObserver")
@MainActor
struct RenderObserverTests {
    @Test func firesAroundComponentBodyEval() {
        let rec = Recorder()
        RenderObserverBox.current = rec
        defer { RenderObserverBox.current = nil }

        var patches: [Patch] = []
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let desc = ComponentDescription(Leaf.self) { Leaf("hi") }
        _ = mount(.component(desc), into: &patches, handles: handles,
                  handlers: handlers, scheduler: nil, depth: 0, path: "", environment: .init())

        #expect(rec.willCount == 1)
        #expect(rec.didCount == 1)
    }
}
