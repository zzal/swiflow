// Sources/SwiflowMacrosPlugin/StateMacro.swift
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

public struct StateMacro: AccessorMacro, PeerMacro {

    // MARK: - AccessorMacro

    public static func expansion(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        guard let varDecl = declaration.as(VariableDeclSyntax.self) else {
            return []   // diagnosed by peer macro path
        }

        // Reject `let`.
        guard varDecl.bindingSpecifier.tokenKind == .keyword(.var) else {
            context.diagnose(Diagnostic(
                node: Syntax(varDecl),
                message: StateMacroDiagnostic.requiresVar
            ))
            return []
        }

        // Reject multi-binding (`@State var a: Int = 0, b: Int = 0`) — the
        // peer path emits the actionable diagnostic; the accessor bails
        // silently so no duplicate is reported.
        guard varDecl.bindings.count == 1 else { return [] }

        // Reject user-supplied accessor blocks (didSet/willSet/get/set).
        guard let binding = varDecl.bindings.first else { return [] }
        if let accessorBlock = binding.accessorBlock {
            context.diagnose(Diagnostic(
                node: Syntax(varDecl),
                message: isComputedProperty(accessorBlock)
                    ? StateMacroDiagnostic.computedPropertyRejected
                    : StateMacroDiagnostic.userDidSetRejected
            ))
            return []
        }

        // Require a type annotation (peer macro diagnoses this; accessor
        // must also bail to leave the source unchanged).
        guard binding.typeAnnotation != nil else {
            return []   // peer macro emits the diagnostic
        }

        guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else {
            return []
        }

        // Emit a didSet that (1) drops the write when it originates from a
        // superseded/dead `.task` (reverting to oldValue — Swift does not
        // re-fire didSet for an in-observer assignment), then (2) marks the
        // owner dirty. Runtime fields are emitted by @Component on the class.
        let didSet: AccessorDeclSyntax = """
            didSet {
                if SwiflowTaskRuntime.shouldDropWrite() {
                    \(raw: name) = oldValue
                    return
                }
                if let s = runtimeScheduler, let o = runtimeOwner {
                    s.markDirty(o)
                }
            }
            """
        return [didSet]
    }

    // MARK: - PeerMacro

    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let varDecl = declaration.as(VariableDeclSyntax.self),
              let binding = varDecl.bindings.first,
              let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier else {
            return []
        }

        // Reject `let` (also diagnosed in accessor expansion).
        guard varDecl.bindingSpecifier.tokenKind == .keyword(.var) else {
            return []   // accessor path emitted the diagnostic
        }

        // Reject multi-binding: each `@State` cell needs its own declaration
        // (the accessor role can't apply to a multi-binding var, and the peer
        // would otherwise emit a duplicate `$first` per binding). Diagnosed
        // HERE (not the accessor path) because the compiler skips the accessor
        // expansion for multi-binding vars but still runs the peer.
        guard varDecl.bindings.count == 1 else {
            context.diagnose(Diagnostic(
                node: Syntax(varDecl),
                message: StateMacroDiagnostic.requiresSingleBinding
            ))
            return []
        }

        // Reject user-supplied accessor blocks — peer should not emit either.
        guard binding.accessorBlock == nil else {
            return []   // accessor path emitted the diagnostic
        }

        // Type annotation is required so we can emit Binding<T>.
        guard let typeAnno = binding.typeAnnotation else {
            context.diagnose(Diagnostic(
                node: Syntax(varDecl),
                message: StateMacroDiagnostic.requiresType
            ))
            return []
        }
        let valueType = typeAnno.type.trimmedDescription
        let name = identifier.text
        // The $ projection copies the property's own declared access (the
        // effective-access rule: an unannotated var is internal even on a
        // public class), so a public component's public @State is bindable
        // cross-module. NB: on a `private(set)` var the projection still
        // exposes writes at the getter's access — @State + private(set) is
        // a contradiction (bindings exist to write); avoid combining them.
        let access = SynthesizedAccess.keyword(for: varDecl.modifiers)

        // `$name` reads/writes the backing `name`, which @Component now isolates
        // to @MainActor (bare → memberAttribute-injected; explicit @MainActor →
        // written). A peer macro can't see the enclosing type's attributes, so it
        // stamps @MainActor unconditionally — always correct, since these three
        // peer macros only ever apply to @Component members (an always-@MainActor
        // type). Redundant on an explicit-@MainActor class, exactly like the
        // @Component-emitted `stateCells`.
        let projected: DeclSyntax = """
            @MainActor \(raw: access)var $\(raw: name): Binding<\(raw: valueType)> {
                Binding(
                    get: { [unowned self] in
                        self.\(raw: name)
                    },
                    set: { [unowned self] in
                        self.\(raw: name) = $0
                    }
                )
            }
            """
        return [projected]
    }
}

// isComputedProperty moved to AccessorIntrospection.swift — now shared with
// @MutationState/@ReducerState, whose diagnostics split mirrors this one.

enum StateMacroDiagnostic: DiagnosticMessage {
    case requiresVar
    case requiresType
    case requiresSingleBinding
    case userDidSetRejected
    case computedPropertyRejected

    var message: String {
        switch self {
        case .requiresVar:
            return "@State requires a `var` — state cells must be mutable."
        case .requiresType:
            return "@State requires an explicit type annotation (e.g. `@State var count: Int = 0`)."
        case .requiresSingleBinding:
            return "@State must be applied to a single property declaration; declare each state cell separately (e.g. `@State var width: Double = 0` on its own line)."
        case .userDidSetRejected:
            return "@State properties cannot declare their own didSet; move the side effect into a method."
        case .computedPropertyRejected:
            return "@State cannot be applied to a computed property — only stored properties. Remove the computed body, or drop @State if this isn't meant to be a state cell."
        }
    }

    var diagnosticID: MessageID {
        MessageID(domain: "SwiflowMacros", id: "\(self)")
    }

    var severity: DiagnosticSeverity { .error }
}
