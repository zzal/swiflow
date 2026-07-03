// Tests/SwiflowTests/Reactivity/ReducerComponentTests.swift
import Testing
@testable import Swiflow

private struct Wizard: Reducer {
    struct State: Equatable { var step = 0 }
    enum Action { case next, back }
    var initialState: State { .init() }
    func reduce(into s: inout State, _ a: Action) {
        switch a {
        case .next where s.step < 2: s.step += 1
        case .back where s.step > 0: s.step -= 1
        default: break
        }
    }
}

@Component
private final class WizardComp {
    @ReducerState var flow: Wizard
    var body: VNode { .text("step \($flow.state.step)") }
}

@Suite("Reducer + @Component integration")
@MainActor
struct ReducerComponentTests {
    @Test("send through a wired @ReducerState updates state and marks dirty")
    func endToEnd() {
        var marks = 0
        let scheduler = SyncScheduler { _ in marks += 1 }
        let c = WizardComp()
        let owner = AnyComponent(c)   // keep strong ref so the weak var in the runtime stays live
        c.bind(owner: owner, scheduler: scheduler)   // macro-emitted wiring

        #expect(c.$flow.state.step == 0)
        c.$flow.send(.next)
        scheduler.flush()
        #expect(c.$flow.state.step == 1)
        #expect(marks >= 1)
        c.$flow.send(.back); c.$flow.send(.back)   // clamped at 0
        #expect(c.$flow.state.step == 0)
    }
}
