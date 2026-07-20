// Tests/SwiflowMacrosTests/PeerGuardDirectTests.swift
//
// Direct-invocation coverage for @State/@Persisted's peer-path guards.
// These shapes CANNOT be pinned through assertMacroExpansion: the test
// harness injects its own "peer macro can only be applied to a single
// variable" error for multi-binding vars (which the real compiler never
// emits — it runs the peer and relies on these guards), and for tuple
// patterns the compiler skips the accessor role entirely, making the peer
// diagnostic the ONLY thing standing between the user and silently
// non-reactive plain storage. Calling the peer expansion directly on
// parsed syntax is the one vehicle that exercises the guards themselves.
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftSyntaxMacroExpansion
import XCTest
@testable import SwiflowMacrosPlugin

final class PeerGuardDirectTests: XCTestCase {

    /// Runs `macro`'s peer expansion over the declaration parsed from
    /// `source` and returns (emitted peer count, diagnostic messages).
    private func runPeer(
        _ macro: PeerMacro.Type,
        attribute: String,
        on source: DeclSyntax
    ) throws -> (peers: Int, messages: [String]) {
        let attr = AttributeSyntax(attributeName: TypeSyntax(stringLiteral: attribute))
        let context = BasicMacroExpansionContext()
        let peers = try macro.expansion(of: attr, providingPeersOf: source, in: context)
        return (peers.count, context.diagnostics.map { $0.diagMessage.message })
    }

    // MARK: - Tuple / wildcard patterns (the silent-guarantee-break shape)

    func testStateTuplePatternIsDiagnosed() throws {
        let decl: DeclSyntax = "var (width, height) = (0.0, 0.0)"
        let result = try runPeer(StateMacro.self, attribute: "State", on: decl)
        XCTAssertEqual(result.peers, 0)
        XCTAssertEqual(result.messages.count, 1)
        XCTAssertTrue(result.messages[0].contains("single property declaration"),
                      "got: \(result.messages)")
    }

    func testPersistedTuplePatternIsDiagnosed() throws {
        let decl: DeclSyntax = #"var (theme, locale) = ("light", "en")"#
        let result = try runPeer(PersistedMacro.self, attribute: "Persisted", on: decl)
        XCTAssertEqual(result.peers, 0)
        XCTAssertEqual(result.messages.count, 1)
        XCTAssertTrue(result.messages[0].contains("single property declaration"),
                      "got: \(result.messages)")
    }

    func testStateWildcardPatternIsDiagnosed() throws {
        let decl: DeclSyntax = "var _ = 0"
        let result = try runPeer(StateMacro.self, attribute: "State", on: decl)
        XCTAssertEqual(result.peers, 0)
        XCTAssertEqual(result.messages.count, 1)
    }

    // MARK: - Multi-binding (harness diverges from the real compiler here)

    func testStateMultiBindingIsDiagnosed() throws {
        let decl: DeclSyntax = "var a: Int = 0, b: Int = 0"
        let result = try runPeer(StateMacro.self, attribute: "State", on: decl)
        XCTAssertEqual(result.peers, 0)
        XCTAssertEqual(result.messages.count, 1)
        XCTAssertTrue(result.messages[0].contains("single property declaration"),
                      "got: \(result.messages)")
    }

    func testPersistedMultiBindingIsDiagnosed() throws {
        let decl: DeclSyntax = #"var a: String = "x", b: String = "y""#
        let result = try runPeer(PersistedMacro.self, attribute: "Persisted", on: decl)
        XCTAssertEqual(result.peers, 0)
        XCTAssertEqual(result.messages.count, 1)
    }

    // MARK: - Control: a well-formed cell emits its peer with no diagnostics

    func testStateWellFormedEmitsProjectionSilently() throws {
        let decl: DeclSyntax = "var count: Int = 0"
        let result = try runPeer(StateMacro.self, attribute: "State", on: decl)
        XCTAssertEqual(result.peers, 1)
        XCTAssertTrue(result.messages.isEmpty, "got: \(result.messages)")
    }
}
