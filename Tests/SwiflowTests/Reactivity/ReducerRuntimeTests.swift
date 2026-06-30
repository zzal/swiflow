// Tests/SwiflowTests/Reactivity/ReducerRuntimeTests.swift
import Testing
@testable import Swiflow

@MainActor private final class RStub: Component { var body: VNode { .text("") } }

private struct Counter: Reducer {
    struct State: Equatable { var count = 0 }
    enum Action { case inc, reset }
    var initialState: State { .init() }
    func reduce(into s: inout State, _ a: Action) {
        switch a { case .inc: s.count += 1; case .reset: s.count = 0 }
    }
}

@Suite("Reducer runtime")
@MainActor
struct ReducerRuntimeTests {

    @Test("pure reduce: actions transform state without any wiring")
    func pureReduce() {
        let r = Counter()
        var s = r.initialState
        r.reduce(into: &s, .inc)
        r.reduce(into: &s, .inc)
        #expect(s.count == 2)
        r.reduce(into: &s, .reset)
        #expect(s.count == 0)
    }

    @Test("send transforms state, seeds from initialState, and marks the owner dirty")
    func sendUpdatesAndMarksDirty() {
        var marks = 0
        let scheduler = SyncScheduler { _ in marks += 1 }
        let owner = AnyComponent(RStub())
        let runtime = ReducerRuntime<Counter>()
        runtime.wire(owner: owner, scheduler: scheduler)

        let reducer = Counter()
        #expect(runtime.seededState(reducer).count == 0)
        runtime.send(reducer, .inc)
        scheduler.flush()
        #expect(runtime.seededState(reducer).count == 1)
        #expect(marks >= 1)
    }
}
