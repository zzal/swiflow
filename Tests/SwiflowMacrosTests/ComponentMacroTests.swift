import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest
@testable import SwiflowMacrosPlugin

private nonisolated(unsafe) let testMacros: [String: Macro.Type] = [
    "Component": ComponentMacro.self,
]

final class ComponentMacroTests: XCTestCase {

    // Test 1: Happy path — extension conformance emitted + runtime members.
    func testHappyPath() {
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
                @State var count: Int = 0
                var body: VNode { .text("hello") }

                private weak var runtimeOwner: AnyComponent?

                private var runtimeScheduler: Scheduler?

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

                func bind(owner: AnyComponent, scheduler: Scheduler) {
                    self.runtimeOwner = owner
                    self.runtimeScheduler = scheduler
                }
            }

            extension Counter: Component, _ComponentRuntime {
            }
            """,
            macros: testMacros
        )
    }

    // Test 2: Non-final class → error diagnostic on the class keyword;
    // no members emitted.
    func testNonFinalDiagnostic() {
        assertMacroExpansion(
            """
            @Component
            class Counter {
                var body: VNode { .text("hello") }
            }
            """,
            expandedSource: """
            class Counter {
                var body: VNode { .text("hello") }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@Component requires 'final' — components cannot be subclassed",
                    line: 2,
                    column: 1
                )
            ],
            macros: testMacros
        )
    }

    // Test 3: Struct → error diagnostic.
    func testStructDiagnostic() {
        assertMacroExpansion(
            """
            @Component
            struct Counter {
                var body: VNode { .text("hello") }
            }
            """,
            expandedSource: """
            struct Counter {
                var body: VNode { .text("hello") }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@Component requires a class — components are reference types in Swiflow",
                    line: 2,
                    column: 1
                )
            ],
            macros: testMacros
        )
    }

    // Test 4: Multiple members without @State — only conformance extension
    // emitted; runtime members emitted; class body unchanged.
    func testMultipleMembersNoModification() {
        assertMacroExpansion(
            """
            @Component
            final class Foo {
                var x: Int = 0
                var computed: Int { x + 1 }
                var body: VNode { .text("hello") }
            }
            """,
            expandedSource: """
            final class Foo {
                var x: Int = 0
                var computed: Int { x + 1 }
                var body: VNode { .text("hello") }

                private weak var runtimeOwner: AnyComponent?

                private var runtimeScheduler: Scheduler?

                @MainActor static let stateCells: [any AnyStateCell] = []

                func bind(owner: AnyComponent, scheduler: Scheduler) {
                    self.runtimeOwner = owner
                    self.runtimeScheduler = scheduler
                }
            }

            extension Foo: Component, _ComponentRuntime {
            }
            """,
            macros: testMacros
        )
    }

    // Test 5: @Component emits _ComponentRuntime conformance + members + cells
    // for @State decorated vars. @State also expands its own
    // didSet accessor + $name peer, so the full expansion is verified here.
    func testEmitsRuntimeMembers() {
        assertMacroExpansion(
            """
            @Component
            final class Counter {
                @State var count: Int = 0
                @State var label: String = "hi"
                var body: VNode { .text("") }
            }
            """,
            expandedSource: """
            final class Counter {
                var count: Int = 0 {
                    didSet {
                        if let s = runtimeScheduler, let o = runtimeOwner {
                            s.markDirty(o)
                        }
                    }
                }

                var $count: Binding<Int> {
                    Binding(
                        get: { [unowned self] in
                            self.count
                        },
                        set: { [unowned self] in
                            self.count = $0
                        }
                    )
                }
                var label: String = "hi" {
                    didSet {
                        if let s = runtimeScheduler, let o = runtimeOwner {
                            s.markDirty(o)
                        }
                    }
                }

                var $label: Binding<String> {
                    Binding(
                        get: { [unowned self] in
                            self.label
                        },
                        set: { [unowned self] in
                            self.label = $0
                        }
                    )
                }
                var body: VNode { .text("") }

                private weak var runtimeOwner: AnyComponent?

                private var runtimeScheduler: Scheduler?

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
                    StateCell<Counter>(
                    name: "label",
                    snapshot: {
                        $0.label as Any
                    },
                    restore: { c, v in
                        guard let typed = _hmrCoerce(v, to: String.self) else {
                            return false
                        }
                        c.label = typed
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

            extension Counter: Component, _ComponentRuntime {
            }
            """,
            macros: ["Component": ComponentMacro.self, "State": StateMacro.self]
        )
    }

    // Test 6: @Component on a class without @State emits empty stateCells.
    func testEmptyStateCells() {
        assertMacroExpansion(
            """
            @Component
            final class Static {
                var body: VNode { .text("hi") }
            }
            """,
            expandedSource: """
            final class Static {
                var body: VNode { .text("hi") }

                private weak var runtimeOwner: AnyComponent?

                private var runtimeScheduler: Scheduler?

                @MainActor static let stateCells: [any AnyStateCell] = []

                func bind(owner: AnyComponent, scheduler: Scheduler) {
                    self.runtimeOwner = owner
                    self.runtimeScheduler = scheduler
                }
            }

            extension Static: Component, _ComponentRuntime {
            }
            """,
            macros: ["Component": ComponentMacro.self]
        )
    }

    // Test 7: Optional @State emits snapshot that normalizes .none to
    // HMRNilSentinel and a non-trivial restoreNil. SwiftSyntax splits
    // `c.maybeId.map { $0 as Any }` across lines in its pretty-printer.
    func testOptionalRestoreNilAndSnapshotSentinel() {
        assertMacroExpansion(
            """
            @Component
            final class Counter {
                @State var maybeId: Int? = nil
                var body: VNode { .text("") }
            }
            """,
            expandedSource: """
            final class Counter {
                var maybeId: Int? = nil {
                    didSet {
                        if let s = runtimeScheduler, let o = runtimeOwner {
                            s.markDirty(o)
                        }
                    }
                }

                var $maybeId: Binding<Int?> {
                    Binding(
                        get: { [unowned self] in
                            self.maybeId
                        },
                        set: { [unowned self] in
                            self.maybeId = $0
                        }
                    )
                }
                var body: VNode { .text("") }

                private weak var runtimeOwner: AnyComponent?

                private var runtimeScheduler: Scheduler?

                @MainActor static let stateCells: [any AnyStateCell] = [
                    StateCell<Counter>(
                    name: "maybeId",
                    snapshot: { c in
                        c.maybeId.map {
                            $0 as Any
                        } ?? HMRNilSentinel() as Any
                    },
                    restore: { c, v in
                        guard let typed = _hmrCoerce(v, to: Int?.self) else {
                            return false
                        }
                        c.maybeId = typed
                        return true
                    },
                    restoreNil: { c in
                        c.maybeId = nil
                        return true
                    }
                    ),
                ]

                func bind(owner: AnyComponent, scheduler: Scheduler) {
                    self.runtimeOwner = owner
                    self.runtimeScheduler = scheduler
                }
            }

            extension Counter: Component, _ComponentRuntime {
            }
            """,
            macros: ["Component": ComponentMacro.self, "State": StateMacro.self]
        )
    }
}
