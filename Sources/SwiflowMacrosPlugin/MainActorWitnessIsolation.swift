// Sources/SwiflowMacrosPlugin/MainActorWitnessIsolation.swift
import SwiftSyntax
import SwiftSyntaxMacros

/// Shared `@attached(memberAttribute)` logic for `@QueryType` / `@MutationType`.
///
/// `Query` and `Mutation` are `@MainActor` protocols. When the macro synthesizes
/// conformance via a generated `extension X: Query {}`, Swift does NOT infer the
/// protocol's global actor onto the primary type (unlike a hand-written
/// `struct X: Query`, where primary-declaration conformance does). The witnesses
/// would then be nonisolated and could not synchronously touch `@MainActor` state
/// — e.g. `optimistic` calling the `@MainActor` `OptimisticEdit.update`.
///
/// So the macro isolates the witnesses itself: functions (`fetch` / `perform` /
/// `optimistic` / `invalidations`) and any static stored state get `@MainActor`.
/// Instance stored properties are left nonisolated so the value stays a plain
/// value (constructed off the main actor, passed by value into `query`/`mutation`).
/// This makes bare `@QueryType struct Foo { ... }` isolation-safe with no
/// `: Query` and no hand-written `@MainActor`.
enum MainActorWitnessIsolation {
    static func attributes(for member: some DeclSyntaxProtocol) -> [AttributeSyntax] {
        if member.is(FunctionDeclSyntax.self) {
            return ["@MainActor"]
        }
        if let varDecl = member.as(VariableDeclSyntax.self),
           varDecl.modifiers.contains(where: { $0.name.tokenKind == .keyword(.static) }) {
            return ["@MainActor"]
        }
        return []
    }
}
