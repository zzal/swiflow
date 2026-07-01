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
                @State
                @MainActor var count: Int = 0
                @MainActor
                var body: VNode { .text("hello") }

                @MainActor init() {
                }

                @MainActor private weak var runtimeOwner: AnyComponent?

                @MainActor private var runtimeScheduler: Scheduler?

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
                @MainActor
                var x: Int = 0
                @MainActor
                var computed: Int { x + 1 }
                @MainActor
                var body: VNode { .text("hello") }

                @MainActor init() {
                }

                @MainActor private weak var runtimeOwner: AnyComponent?

                @MainActor private var runtimeScheduler: Scheduler?

                @MainActor static let stateCells: [any AnyStateCell] = []

                @MainActor func bind(owner: AnyComponent, scheduler: Scheduler) {
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
                @MainActor var count: Int = 0 {
                    didSet {
                        if SwiflowTaskRuntime.shouldDropWrite() {
                            count = oldValue
                            return
                        }
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
                @MainActor var label: String = "hi" {
                    didSet {
                        if SwiflowTaskRuntime.shouldDropWrite() {
                            label = oldValue
                            return
                        }
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
                @MainActor
                var body: VNode { .text("") }

                @MainActor init() {
                }

                @MainActor private weak var runtimeOwner: AnyComponent?

                @MainActor private var runtimeScheduler: Scheduler?

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

                @MainActor func bind(owner: AnyComponent, scheduler: Scheduler) {
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
                @MainActor
                var body: VNode { .text("hi") }

                @MainActor init() {
                }

                @MainActor private weak var runtimeOwner: AnyComponent?

                @MainActor private var runtimeScheduler: Scheduler?

                @MainActor static let stateCells: [any AnyStateCell] = []

                @MainActor func bind(owner: AnyComponent, scheduler: Scheduler) {
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
                @MainActor var maybeId: Int? = nil {
                    didSet {
                        if SwiflowTaskRuntime.shouldDropWrite() {
                            maybeId = oldValue
                            return
                        }
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
                @MainActor
                var body: VNode { .text("") }

                @MainActor init() {
                }

                @MainActor private weak var runtimeOwner: AnyComponent?

                @MainActor private var runtimeScheduler: Scheduler?

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

                @MainActor func bind(owner: AnyComponent, scheduler: Scheduler) {
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

    // Test 8: Long-spelling Optional<Int> must expand identically to Int? —
    // same sentinel-normalizing snapshot and working restoreNil.
    // (Audit HIGH: hasSuffix("?") mis-classified Optional<T> as non-optional.)
    func testOptionalLongSpellingRestoreNilAndSnapshotSentinel() {
        assertMacroExpansion(
            """
            @Component
            final class Counter {
                @State var maybeId: Optional<Int> = nil
                var body: VNode { .text("") }
            }
            """,
            expandedSource: """
            final class Counter {
                @MainActor var maybeId: Optional<Int> = nil {
                    didSet {
                        if SwiflowTaskRuntime.shouldDropWrite() {
                            maybeId = oldValue
                            return
                        }
                        if let s = runtimeScheduler, let o = runtimeOwner {
                            s.markDirty(o)
                        }
                    }
                }

                var $maybeId: Binding<Optional<Int>> {
                    Binding(
                        get: { [unowned self] in
                            self.maybeId
                        },
                        set: { [unowned self] in
                            self.maybeId = $0
                        }
                    )
                }
                @MainActor
                var body: VNode { .text("") }

                @MainActor init() {
                }

                @MainActor private weak var runtimeOwner: AnyComponent?

                @MainActor private var runtimeScheduler: Scheduler?

                @MainActor static let stateCells: [any AnyStateCell] = [
                    StateCell<Counter>(
                    name: "maybeId",
                    snapshot: { c in
                        c.maybeId.map {
                            $0 as Any
                        } ?? HMRNilSentinel() as Any
                    },
                    restore: { c, v in
                        guard let typed = _hmrCoerce(v, to: Optional<Int>.self) else {
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

                @MainActor func bind(owner: AnyComponent, scheduler: Scheduler) {
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

    // Test: bare @Component auto-injects @MainActor onto user + synthesized members.
    func testAutoInjectsMainActorOnBareComponent() {
        assertMacroExpansion(
            """
            @Component
            final class Counter {
                @State var count: Int = 0
                var body: VNode { .text("hi") }
                func bump() { count += 1 }
                nonisolated func pure() {}
                struct Nested {}
                typealias ID = Int
                static let tag = "c"
            }
            """,
            expandedSource: """
            final class Counter {
                @State
                @MainActor var count: Int = 0
                @MainActor
                var body: VNode { .text("hi") }
                @MainActor
                func bump() { count += 1 }
                nonisolated func pure() {}
                struct Nested {}
                typealias ID = Int
                @MainActor
                static let tag = "c"

                @MainActor init() {
                }

                @MainActor private weak var runtimeOwner: AnyComponent?

                @MainActor private var runtimeScheduler: Scheduler?

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

    // Test: an explicit @MainActor @Component skips auto-injection (byte-identical).
    func testExplicitMainActorSkipsAutoInjection() {
        assertMacroExpansion(
            """
            @MainActor
            @Component
            final class Counter {
                @State var count: Int = 0
                var body: VNode { .text("hello") }
            }
            """,
            expandedSource: """
            @MainActor
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

    // Test 9: Swift.Optional<Int> (fully-qualified) must also expand with
    // sentinel-normalizing snapshot + working restoreNil.
    func testOptionalSwiftQualifiedSpellingRestoreNilAndSnapshotSentinel() {
        assertMacroExpansion(
            """
            @Component
            final class Counter {
                @State var maybeId: Swift.Optional<Int> = nil
                var body: VNode { .text("") }
            }
            """,
            expandedSource: """
            final class Counter {
                @MainActor var maybeId: Swift.Optional<Int> = nil {
                    didSet {
                        if SwiflowTaskRuntime.shouldDropWrite() {
                            maybeId = oldValue
                            return
                        }
                        if let s = runtimeScheduler, let o = runtimeOwner {
                            s.markDirty(o)
                        }
                    }
                }

                var $maybeId: Binding<Swift.Optional<Int>> {
                    Binding(
                        get: { [unowned self] in
                            self.maybeId
                        },
                        set: { [unowned self] in
                            self.maybeId = $0
                        }
                    )
                }
                @MainActor
                var body: VNode { .text("") }

                @MainActor init() {
                }

                @MainActor private weak var runtimeOwner: AnyComponent?

                @MainActor private var runtimeScheduler: Scheduler?

                @MainActor static let stateCells: [any AnyStateCell] = [
                    StateCell<Counter>(
                    name: "maybeId",
                    snapshot: { c in
                        c.maybeId.map {
                            $0 as Any
                        } ?? HMRNilSentinel() as Any
                    },
                    restore: { c, v in
                        guard let typed = _hmrCoerce(v, to: Swift.Optional<Int>.self) else {
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

                @MainActor func bind(owner: AnyComponent, scheduler: Scheduler) {
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
