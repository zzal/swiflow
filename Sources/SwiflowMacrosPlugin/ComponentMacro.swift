// Sources/SwiflowMacrosPlugin/ComponentMacro.swift
import SwiftSyntax
import SwiftSyntaxMacros

public struct ComponentMacro: MemberAttributeMacro, ExtensionMacro {

    // MemberAttributeMacro stub — will be implemented in Task 4.
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingAttributesFor member: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AttributeSyntax] {
        return []
    }

    // ExtensionMacro stub — will be implemented in Task 4.
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        return []
    }
}
