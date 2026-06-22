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

    // A `public` struct gets a public init so the mutation is constructible
    // cross-module (the free memberwise init would only be internal).
    func testPublicStructGetsPublicInit() {
        assertMacroExpansion(
            """
            @MutationType public struct RenameUser {
                let id: Int
                let api: FakeAPI
                func perform(_ newName: String) async throws -> User { try await api.renameUser(id, name: newName) }
            }
            """,
            expandedSource: """
            public struct RenameUser {
                let id: Int
                let api: FakeAPI
                @MainActor
                func perform(_ newName: String) async throws -> User { try await api.renameUser(id, name: newName) }

                public init(id: Int, api: FakeAPI) {
                    self.id = id
                    self.api = api
                }
            }
            """,
            macros: testMacros
        )
    }

    // A `package` struct gets a package init — reachable across the package's
    // modules where the type is, not silently internal.
    func testPackageStructGetsPackageInit() {
        assertMacroExpansion(
            """
            @MutationType package struct RenameUser {
                let id: Int
                let api: FakeAPI
                func perform(_ newName: String) async throws -> User { try await api.renameUser(id, name: newName) }
            }
            """,
            expandedSource: """
            package struct RenameUser {
                let id: Int
                let api: FakeAPI
                @MainActor
                func perform(_ newName: String) async throws -> User { try await api.renameUser(id, name: newName) }

                package init(id: Int, api: FakeAPI) {
                    self.id = id
                    self.api = api
                }
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
