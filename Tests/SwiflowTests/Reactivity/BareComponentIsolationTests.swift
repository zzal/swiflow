// Tests/SwiflowTests/Reactivity/BareComponentIsolationTests.swift
//
// COMPILE-ONLY GATE. `assertMacroExpansion` type-checks nothing and never
// registers the peer macros (@State / @ReducerState), so it cannot catch a
// cross-macro isolation mismatch: @Component's memberAttribute role stamps
// @MainActor onto the BACKING property, but the `$name` projection + runtime
// backing are emitted by SEPARATE peer macros the role can't see. If those
// peer outputs are NOT main-actor, a bare (no explicit @MainActor) @Component
// that touches a `$name` projection fails to type-check — and THIS FILE fails
// to BUILD. Keeping it compiling is the real proof the feature works.
//
// Covered here: @State (the reported case) and @ReducerState (reusing the
// local Reducer pattern). @MutationState needs SwiflowQuery scaffolding, so its
// bare host-compile gate lives in SwiflowQueryTests/MutationIntegrationTests.
import Testing
@testable import Swiflow

// MARK: - @State, bare @Component (no explicit @MainActor)

@Component
private final class _BareStateful {
    @State var count: Int = 0
    var body: VNode {
        _ = $count            // projection must be @MainActor to read backing
        return .text("\(count)")
    }
    func bump() {
        count += 1
        $count.set($count.get() + 1)   // exercise projection get/set closures
    }
}

// MARK: - @ReducerState, bare @Component

private struct _BareWizard: Reducer {
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
private final class _BareReducer {
    @ReducerState var flow: _BareWizard
    var body: VNode {
        // $flow (a @MainActor ReducerHandle over a @MainActor backing) must be
        // reachable from this main-actor body.
        .text("step \($flow.state.step)")
    }
}

// MARK: - Explicit @MainActor @Component still compiles (skip path unchanged)

@MainActor
@Component
private final class _ExplicitStateful {
    @State var count: Int = 0
    var body: VNode {
        _ = $count
        return .text("\(count)")
    }
}

// A trivial runtime assertion so the file is a real (linked) test, not just a
// compile artifact — but the load-bearing check is that it BUILDS at all.
@MainActor
struct BareComponentIsolationTests {
    @Test("bare @Component is main-actor isolated end to end")
    func bareComponentCompilesAndRuns() {
        let c = _BareStateful()
        c.bump()
        #expect(c.count == 2)

        let r = _BareReducer()
        #expect(r.$flow.state.step == 0)
    }
}
