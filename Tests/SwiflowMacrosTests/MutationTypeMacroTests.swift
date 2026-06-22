import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest
@testable import SwiflowMacrosPlugin

private nonisolated(unsafe) let testMacros: [String: Macro.Type] = [
    "MutationType": MutationTypeMacro.self,
]

// These tests assert the MEMBER expansion (the memberwise init only). The
// `extension … : Mutation {}` is intentionally absent: `assertMacroExpansion`
// can't see the declaration's `conformances: Mutation`, so it passes
// `conformingTo: []` and the (production-correct) `!protocols.isEmpty` guard
// returns nothing. The extension emission + conformance + migration guard are
// covered end-to-end in `Tests/SwiflowQueryTests/MutationTypeIntegrationTests`.
// `@MutationType` is the thin sibling of `@QueryType`: conformance + memberwise
// init, no `queryKey`/`@Key`/`prefix` (a mutation has no cache identity).
final class MutationTypeMacroTests: XCTestCase {

    // Canonical: captured dependencies become the memberwise init's parameters.
    func testCanonical() {
        assertMacroExpansion(
            """
            @MutationType struct RenameUser {
                let id: Int
                let api: FakeAPI
                func perform(_ newName: String) async throws -> User { try await api.renameUser(id, name: newName) }
            }
            """,
            expandedSource: """
            struct RenameUser {
                let id: Int
                let api: FakeAPI
                @MainActor
                func perform(_ newName: String) async throws -> User { try await api.renameUser(id, name: newName) }

                init(id: Int, api: FakeAPI) {
                    self.id = id
                    self.api = api
                }
            }
            """,
            macros: testMacros
        )
    }

    // No instance storage (only `static`) → an empty memberwise init.
    func testNoStoredDependencies() {
        assertMacroExpansion(
            """
            @MutationType struct AddTodo {
                static var tempSeq = -1
                func perform(_ title: String) async throws -> Todo { try await api.post(title) }
            }
            """,
            expandedSource: """
            struct AddTodo {
                @MainActor
                static var tempSeq = -1
                @MainActor
                func perform(_ title: String) async throws -> Todo { try await api.post(title) }

                init() {
                }
            }
            """,
            macros: testMacros
        )
    }

    // A hand-written init opts out of synthesis — the macro never fights it.
    func testHandWrittenInitSuppressed() {
        assertMacroExpansion(
            """
            @MutationType struct RenameUser {
                let id: Int
                init(id: Int) { self.id = id }
                func perform(_ newName: String) async throws -> User { try await api.renameUser(id, name: newName) }
            }
            """,
            expandedSource: """
            struct RenameUser {
                let id: Int
                init(id: Int) { self.id = id }
                @MainActor
                func perform(_ newName: String) async throws -> User { try await api.renameUser(id, name: newName) }
            }
            """,
            macros: testMacros
        )
    }

    // @MutationType on a non-struct → diagnostic on the type keyword; nothing emitted.
    func testNonStructDiagnostic() {
        assertMacroExpansion(
            """
            @MutationType final class Bad {
                func perform(_ x: Int) async throws -> Int { x }
            }
            """,
            expandedSource: """
            final class Bad {
                func perform(_ x: Int) async throws -> Int { x }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@MutationType requires a struct — mutations are value types that carry their captured dependencies.",
                    line: 1,
                    column: 21
                )
            ],
            macros: testMacros
        )
    }
}
