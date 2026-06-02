import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest
@testable import SwiflowMacrosPlugin

private nonisolated(unsafe) let mutationTestMacros: [String: Macro.Type] = [
    "Component": ComponentMacro.self,
]

final class ComponentMacroMutationTests: XCTestCase {

    // Test 1 (positive): A class WITH @MutationState → bind wires the
    // runtime via the public _currentRenderQueryClient() accessor.
    // @MutationState is NOT registered here — @Component only *scans* for
    // the attribute name; it never expands it.
    func testBindWiresMutationRuntimeWhenPresent() {
        assertMacroExpansion(
            """
            @Component
            final class C {
                @MutationState var create: CreateTodo
                init() {}
            }
            """,
            expandedSource: """
            final class C {
                @MutationState var create: CreateTodo
                init() {}

                private weak var runtimeOwner: AnyComponent?

                private var runtimeScheduler: Scheduler?

                @MainActor static let stateCells: [any AnyStateCell] = []

                func bind(owner: AnyComponent, scheduler: Scheduler) {
                    self.runtimeOwner = owner
                    self.runtimeScheduler = scheduler
                    _create_mutationRuntime.wire(owner: owner, scheduler: scheduler, client: _currentRenderQueryClient())
                }
            }

            extension C: Component, _ComponentRuntime {
            }
            """,
            macros: mutationTestMacros
        )
    }

    // Test 2 (negative): A class WITHOUT @MutationState → bind body is
    // byte-identical to today (no wire(), no _currentRenderQueryClient,
    // no QueryClient reference).
    func testBindUnchangedWithoutMutation() {
        assertMacroExpansion(
            """
            @Component
            final class C {
                @State var n: Int = 0
                init() {}
            }
            """,
            expandedSource: """
            final class C {
                @State var n: Int = 0
                init() {}

                private weak var runtimeOwner: AnyComponent?

                private var runtimeScheduler: Scheduler?

                @MainActor static let stateCells: [any AnyStateCell] = [
                    StateCell<C>(
                    name: "n",
                    snapshot: {
                        $0.n as Any
                    },
                    restore: { c, v in
                        guard let typed = _hmrCoerce(v, to: Int.self) else {
                            return false
                        }
                        c.n = typed
                        return true
                    },
                    restoreNil: { _ in
                        false
                    }
                    ),
                ]

                func bind(owner: AnyComponent, scheduler: Scheduler) {
                    self.runtimeOwner = owner
                    self.runtimeScheduler = scheduler
                }
            }

            extension C: Component, _ComponentRuntime {
            }
            """,
            macros: mutationTestMacros
        )
    }

    // Test 3: Two @MutationState properties → bind wires both runtimes.
    func testBindWiresMultipleMutationRuntimes() {
        assertMacroExpansion(
            """
            @Component
            final class C {
                @MutationState var create: CreateTodo
                @MutationState var update: UpdateTodo
                init() {}
            }
            """,
            expandedSource: """
            final class C {
                @MutationState var create: CreateTodo
                @MutationState var update: UpdateTodo
                init() {}

                private weak var runtimeOwner: AnyComponent?

                private var runtimeScheduler: Scheduler?

                @MainActor static let stateCells: [any AnyStateCell] = []

                func bind(owner: AnyComponent, scheduler: Scheduler) {
                    self.runtimeOwner = owner
                    self.runtimeScheduler = scheduler
                    _create_mutationRuntime.wire(owner: owner, scheduler: scheduler, client: _currentRenderQueryClient())
                    _update_mutationRuntime.wire(owner: owner, scheduler: scheduler, client: _currentRenderQueryClient())
                }
            }

            extension C: Component, _ComponentRuntime {
            }
            """,
            macros: mutationTestMacros
        )
    }
}
