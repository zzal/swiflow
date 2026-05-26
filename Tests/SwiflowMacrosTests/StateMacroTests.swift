import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest
@testable import SwiflowMacrosPlugin

private nonisolated(unsafe) let testMacros: [String: Macro.Type] = [
    "MacroState": StateMacro.self,
]

final class StateMacroTests: XCTestCase {

    // Test 1: Single Int var — emits didSet + $name peer.
    func testSingleIntState() {
        assertMacroExpansion(
            """
            final class Counter {
                @MacroState var count: Int = 0
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
                @MacroState var maybeId: Int? = nil
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
            }
            """,
            macros: testMacros
        )
    }

    // Test 3: User-defined didSet on a @MacroState var → diagnostic.
    func testUserDidSetIsRejected() {
        assertMacroExpansion(
            """
            final class Counter {
                @MacroState var count: Int = 0 {
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

    // Test 4: Applied to `let` — diagnostic.
    func testRejectsLet() {
        assertMacroExpansion(
            """
            final class Counter {
                @MacroState let count: Int = 0
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
                @MacroState var count = 0
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
}
