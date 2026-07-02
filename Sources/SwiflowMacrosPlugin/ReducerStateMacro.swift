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
        // Reject multi-binding first, with a dedicated message: the compiler
        // silently accepts a peer macro on a multi-binding var (expanding once
        // per binding, each emitting the FIRST name -> duplicate `$name` /
        // backing decls). This guard is the only safety net.
        if let varDecl = declaration.as(VariableDeclSyntax.self),
           varDecl.bindings.count > 1 {
            context.diagnose(Diagnostic(
                node: Syntax(varDecl),
                message: ReducerStateDiagnostic.requiresSingleBinding))
            return []
        }
        guard let varDecl = declaration.as(VariableDeclSyntax.self),
              varDecl.bindingSpecifier.tokenKind == .keyword(.var),
              let binding = varDecl.bindings.first,
              binding.accessorBlock == nil,
              let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier,
              let typeAnno = binding.typeAnnotation else {
            context.diagnose(Diagnostic(
                node: Syntax(declaration),
                message: ReducerStateDiagnostic.requiresVarWithType))
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
        let projection: DeclSyntax = """
            @MainActor var $\(raw: name): ReducerHandle<\(raw: reducerType)> {
                ReducerHandle(runtime: _\(raw: name)_reducerRuntime, reducer: \(raw: name))
            }
            """
        return [runtime, projection]
    }
}

enum ReducerStateDiagnostic: DiagnosticMessage {
    case requiresVarWithType
    case requiresSingleBinding
    var message: String {
        switch self {
        case .requiresVarWithType:
            return "@ReducerState requires a `var` with an explicit Reducer type annotation (e.g. `@ReducerState var flow: Checkout`)."
        case .requiresSingleBinding:
            return "@ReducerState must be applied to a single property declaration; declare each reducer separately (e.g. `@ReducerState var flow: Checkout` on its own line)."
        }
    }
    var diagnosticID: MessageID { MessageID(domain: "SwiflowMacros", id: "\(self)") }
    var severity: DiagnosticSeverity { .error }
}
