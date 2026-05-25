// Sources/SwiflowMacrosPlugin/ComponentMacro.swift
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

public struct ComponentMacro: ExtensionMacro {

    // MARK: - ExtensionMacro

    /// Emits `extension TypeName: Component {}` after validating class shape.
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard let classDecl = declaration.as(ClassDeclSyntax.self) else {
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
