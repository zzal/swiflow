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
        // Tailored diagnostics, one per misuse (the @State standard) — a
        // single folded guard used to tell a `let` author to add a type
        // annotation.
        guard let varDecl = declaration.as(VariableDeclSyntax.self) else {
            // Attached to something that isn't a property at all.
            context.diagnose(Diagnostic(
                node: Syntax(declaration),
                message: MutationStateDiagnostic.requiresVar))
            return []
        }
        // Multi-binding first, with a dedicated message: the compiler
        // silently accepts a peer macro on a multi-binding var (expanding once
        // per binding, each emitting the FIRST name -> duplicate `$name` /
        // backing decls). This guard is the only safety net.
        guard varDecl.bindings.count == 1, let binding = varDecl.bindings.first else {
            context.diagnose(Diagnostic(
                node: Syntax(varDecl),
                message: MutationStateDiagnostic.requiresSingleBinding))
            return []
        }
        guard varDecl.bindingSpecifier.tokenKind == .keyword(.var) else {
            context.diagnose(Diagnostic(
                node: Syntax(varDecl),
                message: MutationStateDiagnostic.requiresVar))
            return []
        }
        guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier else {
            // A tuple (or wildcard) pattern is one binding declaring several
            // properties — the one-property-per-declaration advice is the fix.
            context.diagnose(Diagnostic(
                node: Syntax(varDecl),
                message: MutationStateDiagnostic.requiresSingleBinding))
            return []
        }
        if let accessorBlock = binding.accessorBlock {
            context.diagnose(Diagnostic(
                node: Syntax(varDecl),
                message: isComputedProperty(accessorBlock)
                    ? MutationStateDiagnostic.computedPropertyRejected
                    : MutationStateDiagnostic.userDidSetRejected))
            return []
        }
        guard let typeAnno = binding.typeAnnotation else {
            // Required even with an initializer: the runtime peer below is
            // generic over the written type.
            context.diagnose(Diagnostic(
                node: Syntax(varDecl),
                message: MutationStateDiagnostic.requiresType))
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
        // Projection copies the property's declared access (SynthesizedAccess
        // rule); the backing runtime above stays private — implementation detail.
        let access = SynthesizedAccess.keyword(for: varDecl.modifiers)
        let projection: DeclSyntax = """
            @MainActor \(raw: access)var $\(raw: name): MutationHandle<\(raw: mutationType)> {
                MutationHandle(runtime: _\(raw: name)_mutationRuntime, mutation: \(raw: name))
            }
            """
        return [runtime, projection]
    }
}

enum MutationStateDiagnostic: DiagnosticMessage {
    case requiresVar
    case requiresType
    case requiresSingleBinding
    case userDidSetRejected
    case computedPropertyRejected
    var message: String {
        switch self {
        case .requiresVar:
            return "@MutationState requires a `var` (e.g. `@MutationState var create: CreateTodo`)."
        case .requiresType:
            return "@MutationState requires an explicit type annotation (e.g. `@MutationState var create: CreateTodo`)."
        case .requiresSingleBinding:
            return "@MutationState must be applied to a single property declaration; declare each mutation separately (e.g. `@MutationState var add: AddTodo` on its own line)."
        case .userDidSetRejected:
            return "@MutationState properties cannot declare their own didSet — the property only stores the mutation value; observe runs via the `$`-prefixed handle (e.g. `$create.isPending`)."
        case .computedPropertyRejected:
            return "@MutationState cannot be applied to a computed property — only stored properties. Remove the computed body, or drop @MutationState if this isn't meant to be a mutation handle."
        }
    }
    var diagnosticID: MessageID { MessageID(domain: "SwiflowMacros", id: "\(self)") }
    var severity: DiagnosticSeverity { .error }
}
