// Tests/SwiflowTests/Reactivity/StateWiringTests.swift
import Testing
@testable import Swiflow

@Suite("@State owner wiring via Mirror")
struct StateWiringTests {

    final class Counter: Component {
        @State var n: Int = 0
        @State var label: String = "hi"
        var body: VNode { .text("\(label)=\(n)") }
    }

    final class CountingScheduler: Scheduler {
        var markCount = 0
        var lastMarked: AnyComponent?
        func markDirty(_ component: AnyComponent) {
            markCount += 1
            lastMarked = component
        }
        func flush() {}
    }

    @Test("After mount with a Scheduler, @State mutations call scheduler.markDirty")
    func mountWiresState() {
        let scheduler = CountingScheduler()
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()

        let v = VNode.component(.init(Counter.self) { Counter() })
        let result = diff(
            mounted: nil,
            next: v,
            handles: handles,
            handlers: handlers,
            scheduler: scheduler
        )

        let counter = result.newMountTree.component?.instance as? Counter
        #expect(counter != nil)
        #expect(scheduler.markCount == 0, "Mount itself should not mark anything")

        counter?.n = 5
        #expect(scheduler.markCount == 1, "Mutating @State should call markDirty once")

        counter?.label = "bye"
        #expect(scheduler.markCount == 2, "Mutating a different @State should also mark")
    }

    @Test("Without a Scheduler (nil arg), @State mutations are silent")
    func noSchedulerSilent() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let v = VNode.component(.init(Counter.self) { Counter() })
        let result = diff(
            mounted: nil,
            next: v,
            handles: handles,
            handlers: handlers,
            scheduler: nil
        )
        let counter = result.newMountTree.component?.instance as? Counter
        counter?.n = 99  // must not crash
        #expect(counter?.n == 99)
    }

    @Test("Default diff() signature (no scheduler arg) remains callable for backward compat")
    func defaultSignatureCompat() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let v = VNode.element(ElementData(tag: "p"))
        let result = diff(mounted: nil, next: v, handles: handles, handlers: handlers)
        #expect(result.patches.contains(where: {
            if case .createElement(_, let tag) = $0, tag == "p" { return true }
            return false
        }))
    }
}
