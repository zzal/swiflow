// Sources/SwiflowMacrosPlugin/ReducerStateMacro.swift
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// Peer macro for `@ReducerState var flow: SomeReducer`. Emits a persistent
/// backing `_flow_reducerRuntime` and the `$flow` reactive handle projection.
/// `flow` itself stays a plain stored `var` holding the Reducer.
public struct ReducerStateMacro: PeerMacro {
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
                message: ReducerStateDiagnostic.requiresVar))
            return []
        }
        // Multi-binding first, with a dedicated message: the compiler
        // silently accepts a peer macro on a multi-binding var (expanding once
        // per binding, each emitting the FIRST name -> duplicate `$name` /
        // backing decls). This guard is the only safety net.
        guard varDecl.bindings.count == 1, let binding = varDecl.bindings.first else {
            context.diagnose(Diagnostic(
                node: Syntax(varDecl),
                message: ReducerStateDiagnostic.requiresSingleBinding))
            return []
        }
        guard varDecl.bindingSpecifier.tokenKind == .keyword(.var) else {
            context.diagnose(Diagnostic(
                node: Syntax(varDecl),
                message: ReducerStateDiagnostic.requiresVar,
                fixIts: [MacroFixIt.letToVar(varDecl.bindingSpecifier)]))
            return []
        }
        guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier else {
            // A tuple (or wildcard) pattern is one binding declaring several
            // properties — the one-property-per-declaration advice is the fix.
            context.diagnose(Diagnostic(
                node: Syntax(varDecl),
                message: ReducerStateDiagnostic.requiresSingleBinding))
            return []
        }
        if let accessorBlock = binding.accessorBlock {
            context.diagnose(Diagnostic(
                node: Syntax(varDecl),
                message: isComputedProperty(accessorBlock)
                    ? ReducerStateDiagnostic.computedPropertyRejected
                    : ReducerStateDiagnostic.userDidSetRejected))
            return []
        }
        guard let typeAnno = binding.typeAnnotation else {
            // Required even with an initializer: the runtime peer below is
            // generic over the written type.
            context.diagnose(Diagnostic(
                node: Syntax(varDecl),
                message: ReducerStateDiagnostic.requiresType))
            return []
        }
        let name = identifier.text
        let reducerType = typeAnno.type.trimmedDescription

        // @MainActor unconditionally: @ReducerState only ever applies to a
        // @Component member, and @Component is now always @MainActor (bare →
        // injected, explicit → written). The runtime's @MainActor initializer,
        // the ReducerHandle's @MainActor init, and the projection's read of the
        // @MainActor backing `name` all require it; a peer macro can't inspect
        // the enclosing type, so it stamps directly.
        let runtime: DeclSyntax = """
            @MainActor private let _\(raw: name)_reducerRuntime = ReducerRuntime<\(raw: reducerType)>()
            """
        // Projection copies the property's declared access (SynthesizedAccess
        // rule); the backing runtime above stays private — implementation detail.
        let access = SynthesizedAccess.keyword(for: varDecl.modifiers)
        let projection: DeclSyntax = """
            @MainActor \(raw: access)var $\(raw: name): ReducerHandle<\(raw: reducerType)> {
                ReducerHandle(runtime: _\(raw: name)_reducerRuntime, reducer: \(raw: name))
            }
            """
        return [runtime, projection]
    }
}

enum ReducerStateDiagnostic: DiagnosticMessage {
    case requiresVar
    case requiresType
    case requiresSingleBinding
    case userDidSetRejected
    case computedPropertyRejected
    var message: String {
        switch self {
        case .requiresVar:
            return "@ReducerState requires a `var` (e.g. `@ReducerState var flow: Checkout`)."
        case .requiresType:
            return "@ReducerState requires an explicit type annotation (e.g. `@ReducerState var flow: Checkout`)."
        case .requiresSingleBinding:
            return "@ReducerState must be applied to a single property declaration; declare each reducer separately (e.g. `@ReducerState var flow: Checkout` on its own line)."
        case .userDidSetRejected:
            return "@ReducerState properties cannot declare their own didSet — the property only stores the reducer value; state lives in the runtime, read via the `$`-prefixed handle (e.g. `$flow.state`)."
        case .computedPropertyRejected:
            return "@ReducerState cannot be applied to a computed property — only stored properties. Remove the computed body, or drop @ReducerState if this isn't meant to be a reducer handle."
        }
    }
    var diagnosticID: MessageID { MessageID(domain: "SwiflowMacros", id: "\(self)") }
    var severity: DiagnosticSeverity { .error }
}
