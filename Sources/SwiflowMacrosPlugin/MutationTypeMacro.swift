// Sources/SwiflowMacrosPlugin/MutationTypeMacro.swift
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// `@MutationType` synthesizes `Mutation` conformance for a struct and reuses
/// `InitSynthesis` for the memberwise initializer (the test seam). It is the thin
/// sibling of `@QueryType`: a mutation has no cache identity, so there is no
/// `queryKey` / `@Key` / `prefix` — only the conformance plus the init. `perform`
/// (and the optional `optimistic` / `invalidations`) stay hand-written. A
/// hand-written init is never fought.
public struct MutationTypeMacro: ExtensionMacro, MemberMacro {

    // MARK: ExtensionMacro

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard declaration.is(StructDeclSyntax.self) else {
            context.diagnose(Diagnostic(
                node: nonStructKeyword(declaration),
                message: MutationTypeDiagnostic.requiresStruct))
            return []
        }
        // Respect `conformingTo`: emit only the conformances still missing, so a
        // migration `@MutationType struct Foo: Mutation` doesn't double-conform.
        // (`Mutation`, like `Query`, is a public protocol a user may already have
        // declared by hand — unlike @Component's private runtime contracts, which
        // is why @Component can emit its extension unconditionally and this can't.)
        guard !protocols.isEmpty else { return [] }
        let list = protocols.map { $0.trimmedDescription }.joined(separator: ", ")
        return [try ExtensionDeclSyntax("extension \(type): \(raw: list) {}")]
    }

    // MARK: MemberMacro

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            return []   // non-struct already diagnosed in the extension path
        }
        let isPublic = structDecl.modifiers.contains {
            $0.name.tokenKind == .keyword(.public) || $0.name.tokenKind == .keyword(.open)
        }
        // Memberwise init — unless the user wrote their own (InitSynthesis returns nil).
        guard let initDecl = InitSynthesis.memberwiseInit(for: structDecl, isPublic: isPublic) else {
            return []
        }
        return [initDecl]
    }

    // MARK: - Helpers

    private static func nonStructKeyword(_ declaration: some DeclGroupSyntax) -> Syntax {
        if let c = declaration.as(ClassDeclSyntax.self) { return Syntax(c.classKeyword) }
        if let e = declaration.as(EnumDeclSyntax.self) { return Syntax(e.enumKeyword) }
        if let a = declaration.as(ActorDeclSyntax.self) { return Syntax(a.actorKeyword) }
        return Syntax(declaration)
    }
}

enum MutationTypeDiagnostic: DiagnosticMessage {
    case requiresStruct

    var message: String {
        switch self {
        case .requiresStruct:
            return "@MutationType requires a struct — mutations are value types that carry their captured dependencies."
        }
    }
    var diagnosticID: MessageID { MessageID(domain: "SwiflowMacros", id: "\(self)") }
    var severity: DiagnosticSeverity { .error }
}
