import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest
@testable import SwiflowMacrosPlugin

private nonisolated(unsafe) let testMacros: [String: Macro.Type] = [
    "QueryType": QueryTypeMacro.self,
    "Key": KeyMacro.self,
]

// @Key intentionally absent. On a multi-binding var, SwiftSyntaxMacrosTestSupport
// adds its own "peer macro can only be applied to a single variable" diagnostic
// that the *real* compiler never emits (verified by host build — it silently
// accepts it). Omitting @Key here isolates @QueryType's own multi-binding guard;
// @Key then passes through verbatim in the expansion.
private nonisolated(unsafe) let queryOnlyMacros: [String: Macro.Type] = [
    "QueryType": QueryTypeMacro.self,
]

// These tests assert the MEMBER expansion (queryKey + init). The `extension … :
// Query {}` is intentionally absent: `assertMacroExpansion` can't see the
// declaration's `conformances: Query`, so it passes `conformingTo: []` and the
// (production-correct) `!protocols.isEmpty` guard returns nothing. The extension
// emission + conformance + migration guard are covered end-to-end in
// `Tests/SwiflowQueryTests/QueryTypeIntegrationTests.swift`. `@Key` is stripped
// because it is in the macro dictionary and expands as a no-op marker.
final class QueryTypeMacroTests: XCTestCase {

    // Canonical: one @Key + a defaulted dependency.
    func testCanonical() {
        assertMacroExpansion(
            """
            @QueryType struct UserByID {
                @Key var id: Int
                var api: FakeAPI = FakeAPI()
                func fetch() async throws -> User { await api.user(id) }
            }
            """,
            expandedSource: """
            struct UserByID {
                var id: Int
                var api: FakeAPI = FakeAPI()
                @MainActor
                func fetch() async throws -> User { await api.user(id) }

                var queryKey: QueryKey {
                    ["UserByID"] + _qkc(id)
                }

                init(id: Int, api: FakeAPI = FakeAPI()) {
                    self.id = id
                    self.api = api
                }
            }
            """,
            macros: testMacros
        )
    }

    // Custom prefix + zero @Key → a static key (just the prefix); empty init.
    func testPrefixAndStaticKey() {
        assertMacroExpansion(
            """
            @QueryType(prefix: "todos") struct TodoList {
                func fetch() async throws -> [Todo] { [] }
            }
            """,
            expandedSource: """
            struct TodoList {
                @MainActor
                func fetch() async throws -> [Todo] { [] }

                var queryKey: QueryKey {
                    ["todos"]
                }

                init() {
                }
            }
            """,
            macros: testMacros
        )
    }

    // Two @Key properties concatenate in source order.
    func testMultipleKeys() {
        assertMacroExpansion(
            """
            @QueryType(prefix: "quakes") struct QuakeFeed {
                @Key var magnitude: String
                @Key var window: String
                func fetch() async throws -> [Quake] { [] }
            }
            """,
            expandedSource: """
            struct QuakeFeed {
                var magnitude: String
                var window: String
                @MainActor
                func fetch() async throws -> [Quake] { [] }

                var queryKey: QueryKey {
                    ["quakes"] + _qkc(magnitude) + _qkc(window)
                }

                init(magnitude: String, window: String) {
                    self.magnitude = magnitude
                    self.window = window
                }
            }
            """,
            macros: testMacros
        )
    }

    // A hand-written queryKey is not fought; the init is still synthesized.
    func testHandWrittenQueryKeySuppressed() {
        assertMacroExpansion(
            """
            @QueryType struct UserByID {
                @Key var id: Int
                var api: FakeAPI = FakeAPI()
                var queryKey: QueryKey { ["users", .int(id)] }
                func fetch() async throws -> User { await api.user(id) }
            }
            """,
            expandedSource: """
            struct UserByID {
                var id: Int
                var api: FakeAPI = FakeAPI()
                var queryKey: QueryKey { ["users", .int(id)] }
                @MainActor
                func fetch() async throws -> User { await api.user(id) }

                init(id: Int, api: FakeAPI = FakeAPI()) {
                    self.id = id
                    self.api = api
                }
            }
            """,
            macros: testMacros
        )
    }

    // A `public` struct gets public witnesses + a public init, so the query is
    // usable cross-module (the free memberwise init would only be internal).
    func testPublicStructGetsPublicMembers() {
        assertMacroExpansion(
            """
            @QueryType public struct UserByID {
                @Key var id: Int
                var api: FakeAPI = FakeAPI()
                func fetch() async throws -> User { await api.user(id) }
            }
            """,
            expandedSource: """
            public struct UserByID {
                var id: Int
                var api: FakeAPI = FakeAPI()
                @MainActor
                func fetch() async throws -> User { await api.user(id) }

                public var queryKey: QueryKey {
                    ["UserByID"] + _qkc(id)
                }

                public init(id: Int, api: FakeAPI = FakeAPI()) {
                    self.id = id
                    self.api = api
                }
            }
            """,
            macros: testMacros
        )
    }

    // A `package` struct gets package witnesses + a package init — reachable
    // across the package's modules where the type is, not silently internal.
    func testPackageStructGetsPackageMembers() {
        assertMacroExpansion(
            """
            @QueryType package struct UserByID {
                @Key var id: Int
                var api: FakeAPI = FakeAPI()
                func fetch() async throws -> User { await api.user(id) }
            }
            """,
            expandedSource: """
            package struct UserByID {
                var id: Int
                var api: FakeAPI = FakeAPI()
                @MainActor
                func fetch() async throws -> User { await api.user(id) }

                package var queryKey: QueryKey {
                    ["UserByID"] + _qkc(id)
                }

                package init(id: Int, api: FakeAPI = FakeAPI()) {
                    self.id = id
                    self.api = api
                }
            }
            """,
            macros: testMacros
        )
    }

    // Isolation is scoped to what needs it: the protocol-witness methods
    // (here `fetch`) and *mutable* static storage (`static var`, global shared
    // state under strict concurrency). A non-witness helper and an immutable
    // `static let` constant are left nonisolated — over-isolating them would
    // make a plain helper or constant unreachable from nonisolated contexts.
    func testIsolatesOnlyWitnessesAndMutableStatics() {
        assertMacroExpansion(
            """
            @QueryType struct Q {
                @Key var id: Int
                static let base = "/api"
                static var hits = 0
                func fetch() async throws -> Int { Self.hits }
                private func helper() -> Int { 0 }
            }
            """,
            expandedSource: """
            struct Q {
                var id: Int
                static let base = "/api"
                @MainActor
                static var hits = 0
                @MainActor
                func fetch() async throws -> Int { Self.hits }
                private func helper() -> Int { 0 }

                var queryKey: QueryKey {
                    ["Q"] + _qkc(id)
                }

                init(id: Int) {
                    self.id = id
                }
            }
            """,
            macros: testMacros
        )
    }

    // @QueryType on a non-struct → diagnostic on the type keyword; nothing emitted.
    func testNonStructDiagnostic() {
        assertMacroExpansion(
            """
            @QueryType final class Bad {
                func fetch() async throws -> Int { 0 }
            }
            """,
            expandedSource: """
            final class Bad {
                func fetch() async throws -> Int { 0 }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@QueryType requires a struct — queries are value types constructed every render.",
                    line: 1,
                    column: 18
                )
            ],
            macros: testMacros
        )
    }

    // @Key without a type annotation → diagnostic (it must be init-injectable).
    func testKeyNeedsTypeDiagnostic() {
        assertMacroExpansion(
            """
            @QueryType struct Q {
                @Key var id = 5
                func fetch() async throws -> Int { 0 }
            }
            """,
            expandedSource: """
            struct Q {
                var id = 5
                @MainActor
                func fetch() async throws -> Int { 0 }

                var queryKey: QueryKey {
                    ["Q"]
                }

                init() {
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@Key requires an explicit type annotation so the key can be injected in tests (e.g. @Key var id: Int).",
                    line: 2,
                    column: 5
                )
            ],
            macros: testMacros
        )
    }

    // @Key on a multi-binding var (`@Key var a: Int, b: Int`) silently turns EACH
    // binding into a key component in a real build (verified: it compiles with no
    // error) — and @Key order is a cache-identity contract — so @QueryType
    // diagnoses it and drops the malformed key. (@Key stays verbatim here because
    // it is not registered — see `queryOnlyMacros`.)
    func testKeyMultiBindingDiagnostic() {
        assertMacroExpansion(
            """
            @QueryType struct Q {
                @Key var a: Int, b: Int
                func fetch() async throws -> Int { 0 }
            }
            """,
            expandedSource: """
            struct Q {
                @Key var a: Int, b: Int
                @MainActor
                func fetch() async throws -> Int { 0 }

                var queryKey: QueryKey {
                    ["Q"]
                }

                init(a: Int, b: Int) {
                    self.a = a
                    self.b = b
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@Key must mark a single property — give each its own @Key var so the query key's source-order components (a cache-identity contract) stay unambiguous.",
                    line: 2,
                    column: 5
                )
            ],
            macros: queryOnlyMacros
        )
    }
}
