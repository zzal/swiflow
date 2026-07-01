// Sources/SwiflowMacrosPlugin/MutationStateMacro.swift
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// Peer macro for `@MutationState var create: SomeMutation`. Emits a persistent
/// backing `_create_mutationRuntime` and the `$create` reactive handle
/// projection. `create` itself stays a plain stored `var` holding the Mutation.
public struct MutationStateMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let varDecl = declaration.as(VariableDeclSyntax.self),
              varDecl.bindingSpecifier.tokenKind == .keyword(.var),
              let binding = varDecl.bindings.first,
              binding.accessorBlock == nil,
              let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier,
              let typeAnno = binding.typeAnnotation else {
            context.diagnose(Diagnostic(
                node: Syntax(declaration),
                message: MutationStateDiagnostic.requiresVarWithType))
            return []
        }
        let name = identifier.text
        let mutationType = typeAnno.type.trimmedDescription

        // @MainActor unconditionally: @MutationState only ever applies to a
        // @Component member, and @Component is now always @MainActor (bare →
        // injected, explicit → written). The runtime's initializer and the
        // projection's read of the @MainActor backing `name` both require it;
        // a peer macro can't inspect the enclosing type, so it stamps directly.
        let runtime: DeclSyntax = """
            @MainActor private let _\(raw: name)_mutationRuntime = MutationRuntime<\(raw: mutationType)>()
            """
        let projection: DeclSyntax = """
            @MainActor var $\(raw: name): MutationHandle<\(raw: mutationType)> {
                MutationHandle(runtime: _\(raw: name)_mutationRuntime, mutation: \(raw: name))
            }
            """
        return [runtime, projection]
    }
}

enum MutationStateDiagnostic: DiagnosticMessage {
    case requiresVarWithType
    var message: String {
        "@MutationState requires a `var` with an explicit Mutation type annotation (e.g. `@MutationState var create: CreateTodo`)."
    }
    var diagnosticID: MessageID { MessageID(domain: "SwiflowMacros", id: "\(self)") }
    var severity: DiagnosticSeverity { .error }
}
