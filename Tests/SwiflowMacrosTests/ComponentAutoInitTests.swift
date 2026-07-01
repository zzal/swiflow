import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest
@testable import SwiflowMacrosPlugin

// Catalogue item #1 — @MutationState auto-init. @Component synthesizes a
// zero-arg `init()` that default-constructs each @MutationState whose type
// needs no constructor args, *only* when the class declares no init of its
// own. @MutationState is NOT registered here — @Component only scans for the
// attribute name; the peer macro never runs in these golden tests.
private nonisolated(unsafe) let autoInitTestMacros: [String: Macro.Type] = [
    "Component": ComponentMacro.self,
]

final class ComponentAutoInitTests: XCTestCase {

    // A single @MutationState with no user init → synthesized `init()` that
    // default-constructs it.
    func testSynthesizesInitForSingleMutation() {
        assertMacroExpansion(
            """
            @Component
            final class C {
                @MutationState var create: CreateTodo
            }
            """,
            expandedSource: """
            final class C {
                @MutationState
                @MainActor var create: CreateTodo

                @MainActor init() {
                    self.create = CreateTodo()
                }

                @MainActor private weak var runtimeOwner: AnyComponent?

                @MainActor private var runtimeScheduler: Scheduler?

                @MainActor static let stateCells: [any AnyStateCell] = []

                @MainActor func bind(owner: AnyComponent, scheduler: Scheduler) {
                    self.runtimeOwner = owner
                    self.runtimeScheduler = scheduler
                    _create_mutationRuntime.wire(owner: owner, scheduler: scheduler, client: _currentRenderQueryClient())
                }
            }

            extension C: Component, _ComponentRuntime {
            }
            """,
            macros: autoInitTestMacros
        )
    }

    // Multiple @MutationState → the init assigns each, in source order.
    func testSynthesizesInitForMultipleMutations() {
        assertMacroExpansion(
            """
            @Component
            final class C {
                @MutationState var create: CreateTodo
                @MutationState var update: UpdateTodo
            }
            """,
            expandedSource: """
            final class C {
                @MutationState
                @MainActor var create: CreateTodo
                @MutationState
                @MainActor var update: UpdateTodo

                @MainActor init() {
                    self.create = CreateTodo()
                    self.update = UpdateTodo()
                }

                @MainActor private weak var runtimeOwner: AnyComponent?

                @MainActor private var runtimeScheduler: Scheduler?

                @MainActor static let stateCells: [any AnyStateCell] = []

                @MainActor func bind(owner: AnyComponent, scheduler: Scheduler) {
                    self.runtimeOwner = owner
                    self.runtimeScheduler = scheduler
                    _create_mutationRuntime.wire(owner: owner, scheduler: scheduler, client: _currentRenderQueryClient())
                    _update_mutationRuntime.wire(owner: owner, scheduler: scheduler, client: _currentRenderQueryClient())
                }
            }

            extension C: Component, _ComponentRuntime {
            }
            """,
            macros: autoInitTestMacros
        )
    }

    // A user-written init opts out of synthesis entirely — even an empty one.
    // The memberAttribute role still stamps the user's init() with @MainActor.
    func testUserInitSuppressesSynthesis() {
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
                @MutationState
                @MainActor var create: CreateTodo
                @MainActor
                init() {}

                @MainActor private weak var runtimeOwner: AnyComponent?

                @MainActor private var runtimeScheduler: Scheduler?

                @MainActor static let stateCells: [any AnyStateCell] = []

                @MainActor func bind(owner: AnyComponent, scheduler: Scheduler) {
                    self.runtimeOwner = owner
                    self.runtimeScheduler = scheduler
                    _create_mutationRuntime.wire(owner: owner, scheduler: scheduler, client: _currentRenderQueryClient())
                }
            }

            extension C: Component, _ComponentRuntime {
            }
            """,
            macros: autoInitTestMacros
        )
    }

    // A public class gets a `public init()` so it can be constructed
    // cross-module — matching the public witness convention.
    func testPublicClassGetsPublicInit() {
        assertMacroExpansion(
            """
            @Component
            public final class C {
                @MutationState var create: CreateTodo
            }
            """,
            expandedSource: """
            public final class C {
                @MutationState
                @MainActor var create: CreateTodo

                @MainActor public init() {
                    self.create = CreateTodo()
                }

                @MainActor private weak var runtimeOwner: AnyComponent?

                @MainActor private var runtimeScheduler: Scheduler?

                @MainActor public static let stateCells: [any AnyStateCell] = []

                @MainActor public func bind(owner: AnyComponent, scheduler: Scheduler) {
                    self.runtimeOwner = owner
                    self.runtimeScheduler = scheduler
                    _create_mutationRuntime.wire(owner: owner, scheduler: scheduler, client: _currentRenderQueryClient())
                }
            }

            extension C: Component, _ComponentRuntime {
            }
            """,
            macros: autoInitTestMacros
        )
    }

    // A package class gets a `package init()` + package witnesses so it can be
    // constructed across the package's modules — the gap a `public`-only access
    // check left (a package class silently got an internal init).
    func testPackageClassGetsPackageInit() {
        assertMacroExpansion(
            """
            @Component
            package final class C {
                @MutationState var create: CreateTodo
            }
            """,
            expandedSource: """
            package final class C {
                @MutationState
                @MainActor var create: CreateTodo

                @MainActor package init() {
                    self.create = CreateTodo()
                }

                @MainActor private weak var runtimeOwner: AnyComponent?

                @MainActor private var runtimeScheduler: Scheduler?

                @MainActor package static let stateCells: [any AnyStateCell] = []

                @MainActor package func bind(owner: AnyComponent, scheduler: Scheduler) {
                    self.runtimeOwner = owner
                    self.runtimeScheduler = scheduler
                    _create_mutationRuntime.wire(owner: owner, scheduler: scheduler, client: _currentRenderQueryClient())
                }
            }

            extension C: Component, _ComponentRuntime {
            }
            """,
            macros: autoInitTestMacros
        )
    }

    // A @State property carries its own default, so the synthesized init
    // assigns only the mutation — never the state cell.
    func testStateWithDefaultNotAssignedInInit() {
        assertMacroExpansion(
            """
            @Component
            final class C {
                @State var draft: String = ""
                @MutationState var add: AddTodo
            }
            """,
            expandedSource: """
            final class C {
                @State
                @MainActor var draft: String = ""
                @MutationState
                @MainActor var add: AddTodo

                @MainActor init() {
                    self.add = AddTodo()
                }

                @MainActor private weak var runtimeOwner: AnyComponent?

                @MainActor private var runtimeScheduler: Scheduler?

                @MainActor static let stateCells: [any AnyStateCell] = [
                    StateCell<C>(
                    name: "draft",
                    snapshot: {
                        $0.draft as Any
                    },
                    restore: { c, v in
                        guard let typed = _hmrCoerce(v, to: String.self) else {
                            return false
                        }
                        c.draft = typed
                        return true
                    },
                    restoreNil: { _ in
                        false
                    }
                    ),
                ]

                @MainActor func bind(owner: AnyComponent, scheduler: Scheduler) {
                    self.runtimeOwner = owner
                    self.runtimeScheduler = scheduler
                    _add_mutationRuntime.wire(owner: owner, scheduler: scheduler, client: _currentRenderQueryClient())
                }
            }

            extension C: Component, _ComponentRuntime {
            }
            """,
            macros: autoInitTestMacros
        )
    }

    // No @MutationState → still synthesizes a @MainActor init() to prevent
    // Swift from generating a nonisolated default init that would conflict
    // with the @MainActor-isolated synthesized storage properties.
    func testNoMutationNoSynthesizedInit() {
        assertMacroExpansion(
            """
            @Component
            final class C {
                @State var n: Int = 0
            }
            """,
            expandedSource: """
            final class C {
                @State
                @MainActor var n: Int = 0

                @MainActor init() {
                }

                @MainActor private weak var runtimeOwner: AnyComponent?

                @MainActor private var runtimeScheduler: Scheduler?

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

                @MainActor func bind(owner: AnyComponent, scheduler: Scheduler) {
                    self.runtimeOwner = owner
                    self.runtimeScheduler = scheduler
                }
            }

            extension C: Component, _ComponentRuntime {
            }
            """,
            macros: autoInitTestMacros
        )
    }
}
