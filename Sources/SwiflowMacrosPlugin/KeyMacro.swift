// Sources/SwiflowMacrosPlugin/KeyMacro.swift
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// Marker peer macro for `@Key var id: Int` inside a `@QueryType`. It emits **no**
/// peers — its sole job is to survive as a syntactic annotation that the enclosing
/// `@QueryType` member macro reads (in source order) to derive `queryKey`. The only
/// thing it validates is placement: `@Key` must sit on a stored property, since a
/// computed property has no identity to contribute to a cache key.
public struct KeyMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // Stored property = a `var`/`let` binding with no accessor block (a getter
        // means computed; the marker is meaningless there).
        guard let varDecl = declaration.as(VariableDeclSyntax.self),
              varDecl.bindings.first?.accessorBlock == nil else {
            context.diagnose(Diagnostic(
                node: Syntax(declaration),
                message: KeyDiagnostic.requiresStoredProperty))
            return []
        }
        return []
    }
}

enum KeyDiagnostic: DiagnosticMessage {
    case requiresStoredProperty
    var message: String {
        "@Key marks a stored property; computed properties cannot be query-key components."
    }
    var diagnosticID: MessageID { MessageID(domain: "SwiflowMacros", id: "\(self)") }
    var severity: DiagnosticSeverity { .error }
}
