import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest
@testable import SwiflowMacrosPlugin

private nonisolated(unsafe) let reducerTestMacros: [String: Macro.Type] = [
    "Component": ComponentMacro.self,
    "ReducerState": ReducerStateMacro.self,
    "State": StateMacro.self,
]

final class ComponentMacroReducerTests: XCTestCase {

    // Test (a): A @Component with @ReducerState → bind wires the reducer
    // runtime via _<name>_reducerRuntime.wire(owner:scheduler:) and the
    // synthesized init() default-constructs the reducer value.
    func testWiresReducerCell() {
        assertMacroExpansion(
            """
            @Component
            final class Flowy {
                @ReducerState var flow: Checkout
                var body: VNode { .text("") }
            }
            """,
            expandedSource: """
            final class Flowy {
                @MainActor var flow: Checkout

                @MainActor private let _flow_reducerRuntime = ReducerRuntime<Checkout>()

                @MainActor var $flow: ReducerHandle<Checkout> {
                    ReducerHandle(runtime: _flow_reducerRuntime, reducer: flow)
                }
                @MainActor
                var body: VNode { .text("") }

                @MainActor init() {
                    self.flow = Checkout()
                }

                @MainActor private weak var _swiflowOwner: AnyComponent?

                @MainActor private var _swiflowScheduler: Scheduler?

                @MainActor static let stateCells: [any AnyStateCell] = []

                @MainActor func bind(owner: AnyComponent, scheduler: Scheduler) {
                    self._swiflowOwner = owner
                    self._swiflowScheduler = scheduler
                    _flow_reducerRuntime.wire(owner: owner, scheduler: scheduler)
                }
            }

            extension Flowy: Component, _ComponentRuntime {
            }
            """,
            macros: reducerTestMacros
        )
    }

    // Test (b): A reducer-free, mutation-free component must expand
    // identically to ComponentMacroTests.testHappyPath — proves the additive
    // change did not alter reducer-free components. The expected source is kept
    // in sync verbatim with that golden; @State is NOT registered in the macros
    // map so it stays unexpanded, matching that golden exactly.
    func testNoReducerByteIdentical() {
        assertMacroExpansion(
            """
            @Component
            final class Counter {
                @State var count: Int = 0
                var body: VNode { .text("hello") }
            }
            """,
            expandedSource: """
            final class Counter {
                @State
                @MainActor var count: Int = 0
                @MainActor
                var body: VNode { .text("hello") }

                @MainActor init() {
                }

                @MainActor private weak var _swiflowOwner: AnyComponent?

                @MainActor private var _swiflowScheduler: Scheduler?

                @MainActor static let stateCells: [any AnyStateCell] = [
                    StateCell<Counter>(
                    name: "count",
                    snapshot: {
                        $0.count as Any
                    },
                    restore: { c, v in
                        guard let typed = _hmrCoerce(v, to: Int.self) else {
                            return false
                        }
                        c.count = typed
                        return true
                    },
                    restoreNil: { _ in
                        false
                    }
                    ),
                ]

                @MainActor func bind(owner: AnyComponent, scheduler: Scheduler) {
                    self._swiflowOwner = owner
                    self._swiflowScheduler = scheduler
                }
            }

            extension Counter: Component, _ComponentRuntime {
            }
            """,
            macros: ["Component": ComponentMacro.self]
        )
    }
}
