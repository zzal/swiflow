import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest
@testable import SwiflowMacrosPlugin

private nonisolated(unsafe) let testMacros: [String: Macro.Type] = [
    "Component": ComponentMacro.self,
]

final class ComponentMacroTests: XCTestCase {

    // Test 1: Happy path — stored property gets @MainActor; computed property (body) does not;
    // extension conformance is emitted.
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

    // Test 4: Computed property (var with accessor) must NOT get @MainActor.
    func testComputedPropertySkipped() {
        assertMacroExpansion(
            """
            @Component
            final class Foo {
                var x: Int { 42 }
                var body: VNode { .text("hello") }
            }
            """,
            expandedSource: """
            final class Foo {
                var x: Int { 42 }
                var body: VNode { .text("hello") }
            }

            extension Foo: Component {
            }
            """,
            macros: testMacros
        )
    }

    // Test 5: Property already annotated @MainActor must NOT get a duplicate.
    func testAlreadyMainActorNotDuplicated() {
        assertMacroExpansion(
            """
            @Component
            final class Foo {
                @MainActor var x: Int = 0
                var body: VNode { .text("hello") }
            }
            """,
            expandedSource: """
            final class Foo {
                @MainActor var x: Int = 0
                var body: VNode { .text("hello") }
            }

            extension Foo: Component {
            }
            """,
            macros: testMacros
        )
    }

    // Test 6: nonisolated property must NOT get @MainActor.
    func testNonisolatedRespected() {
        assertMacroExpansion(
            """
            @Component
            final class Foo {
                nonisolated var x: Int = 0
                var body: VNode { .text("hello") }
            }
            """,
            expandedSource: """
            final class Foo {
                nonisolated var x: Int = 0
                var body: VNode { .text("hello") }
            }

            extension Foo: Component {
            }
            """,
            macros: testMacros
        )
    }
}
