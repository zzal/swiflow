import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest
@testable import SwiflowMacrosPlugin

private nonisolated(unsafe) let testMacros: [String: Macro.Type] = [
    "State": StateMacro.self,
]

final class StateMacroTests: XCTestCase {

    // Test 1: Single Int var — emits didSet + $name peer.
    func testSingleIntState() {
        assertMacroExpansion(
            """
            final class Counter {
                @State var count: Int = 0
            }
            """,
            expandedSource: """
            final class Counter {
                var count: Int = 0 {
                    didSet {
                        if SwiflowTaskRuntime.shouldDropWrite() {
                            count = oldValue
                            return
                        }
                        if let s = _swiflowScheduler, let o = _swiflowOwner {
                            s.markDirty(o)
                        }
                    }
                }

                @MainActor var $count: Binding<Int> {
                    Binding(
                        get: { [unowned self] in
                            self.count
                        },
                        set: { [unowned self] in
                            self.count = $0
                        }
                    )
                }
            }
            """,
            macros: testMacros
        )
    }

    // Test 2: Optional Int — same shape, propagates `?` to Binding<Int?>.
    func testOptionalState() {
        assertMacroExpansion(
            """
            final class Counter {
                @State var maybeId: Int? = nil
            }
            """,
            expandedSource: """
            final class Counter {
                var maybeId: Int? = nil {
                    didSet {
                        if SwiflowTaskRuntime.shouldDropWrite() {
                            maybeId = oldValue
                            return
                        }
                        if let s = _swiflowScheduler, let o = _swiflowOwner {
                            s.markDirty(o)
                        }
                    }
                }

                @MainActor var $maybeId: Binding<Int?> {
                    Binding(
                        get: { [unowned self] in
                            self.maybeId
                        },
                        set: { [unowned self] in
                            self.maybeId = $0
                        }
                    )
                }
            }
            """,
            macros: testMacros
        )
    }

    // Test 3: User-defined didSet on a @State var → diagnostic.
    func testUserDidSetIsRejected() {
        assertMacroExpansion(
            """
            final class Counter {
                @State var count: Int = 0 {
                    didSet { print("user") }
                }
            }
            """,
            expandedSource: """
            final class Counter {
                var count: Int = 0 {
                    didSet { print("user") }
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@State properties cannot declare their own didSet; move the side effect into a method.",
                    line: 2, column: 5, severity: .error
                ),
            ],
            macros: testMacros
        )
    }

    // Test 3b: Computed property (getter-only shorthand) → distinct diagnostic
    // from the user-didSet case (never wrote a didSet to move).
    func testComputedPropertyIsRejected() {
        assertMacroExpansion(
            """
            final class Counter {
                @State var doubled: Int { 5 }
            }
            """,
            expandedSource: """
            final class Counter {
                var doubled: Int { 5 }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@State cannot be applied to a computed property — only stored properties. Remove the computed body, or drop @State if this isn't meant to be a state cell.",
                    line: 2, column: 5, severity: .error
                ),
            ],
            macros: testMacros
        )
    }

    // Test 3c: Computed property with explicit get/set → same diagnostic as
    // the getter-only shorthand.
    func testComputedPropertyWithGetSetIsRejected() {
        assertMacroExpansion(
            """
            final class Counter {
                @State var doubled: Int {
                    get { 5 }
                    set { }
                }
            }
            """,
            expandedSource: """
            final class Counter {
                var doubled: Int {
                    get { 5 }
                    set { }
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@State cannot be applied to a computed property — only stored properties. Remove the computed body, or drop @State if this isn't meant to be a state cell.",
                    line: 2, column: 5, severity: .error
                ),
            ],
            macros: testMacros
        )
    }

    // Test 4: Applied to `let` — diagnostic.
    func testRejectsLet() {
        assertMacroExpansion(
            """
            final class Counter {
                @State let count: Int = 0
            }
            """,
            expandedSource: """
            final class Counter {
                let count: Int = 0
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@State requires a `var` — state cells must be mutable.",
                    line: 2, column: 5, severity: .error
                ),
            ],
            macros: testMacros
        )
    }

    // Test 5: Missing type annotation → diagnostic.
    func testRequiresTypeAnnotation() {
        assertMacroExpansion(
            """
            final class Counter {
                @State var count = 0
            }
            """,
            expandedSource: """
            final class Counter {
                var count = 0
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@State requires an explicit type annotation (e.g. `@State var count: Int = 0`).",
                    line: 2, column: 5, severity: .error
                ),
            ],
            macros: testMacros
        )
    }

    // Multi-binding: `@State var a: Int = 0, b: Int = 0`.
    // HARNESS/COMPILER DIVERGENCE (see docs + ReducerStateMacroTests): the
    // assertMacroExpansion harness refuses BOTH roles on a multi-binding var
    // (its own two diagnostics below) and never invokes our expansion. The
    // REAL compiler blocks only the accessor but RUNS the peer — where our
    // StateMacroDiagnostic.requiresSingleBinding fires. The real-compiler
    // behavior is covered by the host-compile check recorded in the PR (a
    // committed test can't assert a compile FAILURE).
    func testRejectsMultiBinding() {
        assertMacroExpansion(
            """
            final class Counter {
                @State var a: Int = 0, b: Int = 0
            }
            """,
            expandedSource: """
            final class Counter {
                var a: Int = 0, b: Int = 0
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "accessor macro can only be applied to a single variable", line: 2, column: 5, severity: .error),
                DiagnosticSpec(message: "peer macro can only be applied to a single variable", line: 2, column: 5, severity: .error),
            ],
            macros: testMacros
        )
    }

    // Access propagation: the $ projection copies the property's declared
    // access so a public component's public @State is bindable cross-module
    // (SynthesizedAccess rule — audit Wave-2).
    func testPublicStateEmitsPublicProjection() {
        assertMacroExpansion(
            """
            final class Counter {
                @State public var count: Int = 0
            }
            """,
            expandedSource: """
            final class Counter {
                public var count: Int = 0 {
                    didSet {
                        if SwiflowTaskRuntime.shouldDropWrite() {
                            count = oldValue
                            return
                        }
                        if let s = _swiflowScheduler, let o = _swiflowOwner {
                            s.markDirty(o)
                        }
                    }
                }

                @MainActor public var $count: Binding<Int> {
                    Binding(
                        get: { [unowned self] in
                            self.count
                        },
                        set: { [unowned self] in
                            self.count = $0
                        }
                    )
                }
            }
            """,
            macros: testMacros
        )
    }
}
