// Sources/SwiflowMacrosPlugin/MainActorWitnessIsolation.swift
import SwiftSyntax
import SwiftSyntaxMacros

/// Shared `@attached(memberAttribute)` logic for `@Query` / `@Mutation`.
///
/// `Query` and `Mutation` are `@MainActor` protocols. When the macro synthesizes
/// conformance via a generated `extension X: Query {}`, Swift does NOT infer the
/// protocol's global actor onto the primary type (unlike a hand-written
/// `struct X: Query`, where primary-declaration conformance does). The witnesses
/// would then be nonisolated and could not synchronously touch `@MainActor` state
/// — e.g. `optimistic` calling the `@MainActor` `OptimisticEdit.update`.
///
/// So the macro isolates exactly what needs it: the protocol-witness methods
/// (`fetch` / `perform` / `optimistic` / `invalidations`) and *mutable* static
/// storage (`static var`, which is global shared state under strict concurrency).
/// Everything else is left nonisolated — instance stored properties (so the value
/// stays plain: constructed off the main actor, passed by value into
/// `query`/`mutation`), the author's own non-witness helper methods, and
/// immutable `static let` constants (already Sendable-safe). This keeps bare
/// `@Query struct Foo { ... }` isolation-safe with no `: Query` and no
/// hand-written `@MainActor`, without over-isolating helpers or constants.
enum MainActorWitnessIsolation {
    /// The Query (`fetch`) and Mutation (`perform` / `optimistic` /
    /// `invalidations`) function requirements. Only these need `@MainActor`;
    /// keep in sync with the protocols' method requirements.
    private static let witnessNames: Set<String> = [
        "fetch", "perform", "optimistic", "invalidations",
    ]

    static func attributes(for member: some DeclSyntaxProtocol) -> [AttributeSyntax] {
        // Never stamp a member the author already isolated (explicit @MainActor,
        // another global actor, or nonisolated) — a second global-actor attribute
        // is a compile error. Shares ComponentIsolation's guard (one source of truth).
        if ComponentIsolation.memberHasIsolation(member) { return [] }
        if let fn = member.as(FunctionDeclSyntax.self), witnessNames.contains(fn.name.text) {
            return ["@MainActor"]
        }
        // Mutable static storage is global shared state — it needs main-actor
        // isolation under strict concurrency. An immutable `static let` is
        // already safe, so it stays nonisolated (isolating it would needlessly
        // bar reads from nonisolated contexts).
        if let varDecl = member.as(VariableDeclSyntax.self),
           varDecl.modifiers.contains(where: { $0.name.tokenKind == .keyword(.static) }),
           varDecl.bindingSpecifier.tokenKind == .keyword(.var) {
            return ["@MainActor"]
        }
        return []
    }
}
