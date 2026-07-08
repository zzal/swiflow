// Sources/SwiflowMacrosPlugin/PersistedMacro.swift
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// `@Persisted` — @State's exact shape (dirty-marking didSet + `$name`
/// Binding peer) plus persistence: the didSet also saves through
/// `_PersistedStorageRegistry` (skipped under the hydration flag), and
/// `@Component` synthesizes the mount-time hydration for every member
/// (see ComponentMacro). Key derivation is shared with ComponentMacro via
/// `PersistedKeyDerivation` so the two emission sites cannot drift.
public struct PersistedMacro: AccessorMacro, PeerMacro {

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
                message: PersistedMacroDiagnostic.requiresVar
            ))
            return []
        }

        // Reject multi-binding — the peer path emits the actionable
        // diagnostic; the accessor bails silently so no duplicate is reported.
        guard varDecl.bindings.count == 1 else { return [] }

        // Reject user-supplied accessor blocks (didSet/willSet/get/set).
        guard let binding = varDecl.bindings.first else { return [] }
        if let accessorBlock = binding.accessorBlock {
            context.diagnose(Diagnostic(
                node: Syntax(varDecl),
                message: isComputedProperty(accessorBlock)
                    ? PersistedMacroDiagnostic.computedPropertyRejected
                    : PersistedMacroDiagnostic.userDidSetRejected
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

        // Non-literal explicit key: diagnosed by the peer path; bail here.
        guard !PersistedKeyDerivation.hasNonLiteralKey(node) else { return [] }

        let key = PersistedKeyDerivation.keyExpression(
            explicitKey: PersistedKeyDerivation.explicitKey(from: node),
            propertyName: name
        )

        // @State's exact didSet (drop superseded-task writes, mark dirty)
        // plus the save. The save is skipped while @Component's synthesized
        // hydration flag is set — restoring a stored value must not write
        // it straight back. `try?` mirrors the pre-macro QuakesPage ritual;
        // a quota-exceeded warn is audit Wave-3's separate guardrail.
        let didSet: AccessorDeclSyntax = """
            didSet {
                if SwiflowTaskRuntime.shouldDropWrite() {
                    \(raw: name) = oldValue
                    return
                }
                if let s = runtimeScheduler, let o = runtimeOwner {
                    s.markDirty(o)
                }
                if !_swiflowIsHydrating {
                    let value = \(raw: name)
                    Task { try? await _PersistedStorageRegistry.current.save(value, forKey: \(raw: key)) }
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

        // Reject multi-binding: diagnosed HERE (not the accessor path)
        // because the compiler skips the accessor expansion for
        // multi-binding vars but still runs the peer.
        guard varDecl.bindings.count == 1 else {
            context.diagnose(Diagnostic(
                node: Syntax(varDecl),
                message: PersistedMacroDiagnostic.requiresSingleBinding
            ))
            return []
        }

        // Reject user-supplied accessor blocks — peer should not emit either.
        guard binding.accessorBlock == nil else {
            return []   // accessor path emitted the diagnostic
        }

        // Type annotation is required so we can emit Binding<T> (and so
        // @Component can emit the typed hydration load).
        guard let typeAnno = binding.typeAnnotation else {
            context.diagnose(Diagnostic(
                node: Syntax(varDecl),
                message: PersistedMacroDiagnostic.requiresType
            ))
            return []
        }

        // Explicit key must be a static string literal — it is baked into
        // the emitted storage calls. Diagnosed once, on the peer path.
        guard !PersistedKeyDerivation.hasNonLiteralKey(node) else {
            context.diagnose(Diagnostic(
                node: Syntax(node),
                message: PersistedMacroDiagnostic.keyRequiresStaticString
            ))
            return []
        }

        let valueType = typeAnno.type.trimmedDescription
        let name = identifier.text
        let access = SynthesizedAccess.keyword(for: varDecl.modifiers)

        // Same projection as @State — see StateMacro for the @MainActor
        // rationale (peer macros can't see the enclosing type's attributes;
        // stamping is always correct on @Component members).
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

enum PersistedMacroDiagnostic: DiagnosticMessage {
    case requiresVar
    case requiresType
    case requiresSingleBinding
    case userDidSetRejected
    case computedPropertyRejected
    case keyRequiresStaticString

    var message: String {
        switch self {
        case .requiresVar:
            return "@Persisted requires a `var` — persisted cells must be mutable."
        case .requiresType:
            return "@Persisted requires an explicit type annotation (e.g. `@Persisted var count: Int = 0`)."
        case .requiresSingleBinding:
            return "@Persisted must be applied to a single property declaration; declare each persisted cell separately (e.g. `@Persisted var theme: String = \"light\"` on its own line)."
        case .userDidSetRejected:
            return "@Persisted properties cannot declare their own didSet; move the side effect into a method."
        case .computedPropertyRejected:
            return "@Persisted cannot be applied to a computed property — only stored properties. Remove the computed body, or drop @Persisted if this isn't meant to be a persisted cell."
        case .keyRequiresStaticString:
            return "@Persisted's key must be a static string literal — it is baked into the emitted storage calls. Move dynamic parts into the value, not the key."
        }
    }

    var diagnosticID: MessageID {
        MessageID(domain: "SwiflowMacros", id: "\(self)")
    }

    var severity: DiagnosticSeverity { .error }
}
