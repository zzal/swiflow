import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest
@testable import SwiflowMacrosPlugin

private nonisolated(unsafe) let testMacros: [String: Macro.Type] = [
    "Component": ComponentMacro.self,
]

final class ComponentMacroTests: XCTestCase {

    // Test 1: Happy path — extension conformance emitted; class body unchanged.
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
            }

            extension Counter: Component {
            }
            """,
            macros: testMacros
        )
    }

    // Test 2: Non-final class → error diagnostic on the class keyword.
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

    // Test 4: Multiple members — only conformance extension emitted; class body unchanged.
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
            }

            extension Foo: Component {
            }
            """,
            macros: testMacros
        )
    }
}
