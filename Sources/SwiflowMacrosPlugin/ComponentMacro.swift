import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

public struct ComponentMacro: MemberAttributeMacro, ExtensionMacro {

    // MARK: - MemberAttributeMacro

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingAttributesFor member: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AttributeSyntax] {
        guard let varDecl = member.as(VariableDeclSyntax.self) else { return [] }
        // Skip computed properties (those with an accessor block).
        guard varDecl.bindings.allSatisfy({ $0.accessorBlock == nil }) else { return [] }
        // Skip if @MainActor is already present.
        let hasMainActor = varDecl.attributes.contains {
            guard case .attribute(let attr) = $0,
                  let id = attr.attributeName.as(IdentifierTypeSyntax.self) else { return false }
            return id.name.text == "MainActor"
        }
        guard !hasMainActor else { return [] }
        // Skip if nonisolated is present.
        let hasNonisolated = varDecl.modifiers.contains { $0.name.text == "nonisolated" }
        guard !hasNonisolated else { return [] }
        return [AttributeSyntax(
            attributeName: IdentifierTypeSyntax(name: .identifier("MainActor"))
        )]
    }

    // MARK: - ExtensionMacro

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard let classDecl = declaration.as(ClassDeclSyntax.self) else {
            // Anchor to the type keyword (struct/enum/actor keyword) so the diagnostic
            // lands on the declaration line rather than the leading attribute line.
            let typeKeyword: Syntax
            if let structDecl = declaration.as(StructDeclSyntax.self) {
                typeKeyword = Syntax(structDecl.structKeyword)
            } else if let enumDecl = declaration.as(EnumDeclSyntax.self) {
                typeKeyword = Syntax(enumDecl.enumKeyword)
            } else if let actorDecl = declaration.as(ActorDeclSyntax.self) {
                typeKeyword = Syntax(actorDecl.actorKeyword)
            } else {
                typeKeyword = Syntax(declaration)
            }
            context.diagnose(Diagnostic(
                node: typeKeyword,
                message: ComponentMacroDiagnostic.requiresClass
            ))
            return []
        }
        guard classDecl.modifiers.contains(where: { $0.name.text == "final" }) else {
            context.diagnose(Diagnostic(
                node: Syntax(classDecl.classKeyword),
                message: ComponentMacroDiagnostic.requiresFinal
            ))
            return []
        }
        return [try ExtensionDeclSyntax("extension \(type): Component {}")]
    }
}

enum ComponentMacroDiagnostic: DiagnosticMessage {
    case requiresClass
    case requiresFinal

    var message: String {
        switch self {
        case .requiresClass:
            return "@Component requires a class — components are reference types in Swiflow"
        case .requiresFinal:
            return "@Component requires 'final' — components cannot be subclassed"
        }
    }

    var diagnosticID: MessageID {
        MessageID(domain: "SwiflowMacros", id: "\(self)")
    }

    var severity: DiagnosticSeverity { .error }
}
