// Sources/SwiflowMacrosPlugin/ComponentMacro.swift
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

public struct ComponentMacro: ExtensionMacro, MemberMacro {

    // MARK: - ExtensionMacro

    /// Emits `extension TypeName: Component, _ComponentRuntime {}` after
    /// validating class shape.
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
        return [try ExtensionDeclSyntax("extension \(type): Component, _ComponentRuntime {}")]
    }

    // MARK: - MemberMacro

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let classDecl = declaration.as(ClassDeclSyntax.self) else {
            return []   // already diagnosed by ExtensionMacro path
        }
        // Skip member emission for non-final classes — the ExtensionMacro
        // path already emitted the diagnostic. Returning empty here keeps
        // the expanded source clean (no orphaned members on an invalid decl).
        guard classDecl.modifiers.contains(where: { $0.name.text == "final" }) else {
            return []
        }
        let className = classDecl.name.text

        // Emitted protocol witnesses must match the host class's visibility: a
        // public/package class adopting `_ComponentRuntime` must declare its
        // witnesses at the same access, or they silently narrow to internal and
        // break cross-module construction. `SynthesizedAccess` returns the
        // keyword to copy onto them ("public " / "package " / ""). The
        // `_swiflowOwner` and `_swiflowScheduler` stored properties stay private
        // regardless — they're implementation detail, not part of the protocol.
        let access = SynthesizedAccess.keyword(for: classDecl.modifiers)

        // When the type is NOT already @MainActor, the memberAttribute role will
        // stamp user members — but it never sees these SYNTHESIZED members, so
        // they must isolate themselves. When the type already has @MainActor, emit
        // nothing extra (byte-identical to today; `stateCells` keeps its own
        // @MainActor as it does now).
        let synthActor = ComponentIsolation.hasMainActorAttribute(classDecl.attributes) ? "" : "@MainActor "

        // Whether the user owns construction. When they don't, @Component
        // synthesizes the init — and a non-optional @State with no default
        // would then be left uninitialized, so we diagnose it below (guardrail).
        let hasUserInit = classDecl.memberBlock.members.contains {
            $0.decl.is(InitializerDeclSyntax.self)
        }

        // Scan members for @MacroState or @State. The scanner accepts
        // both during the Phase 15 migration window (Task 4 introduced
        // @MacroState; Task 6 normalized to @State). Both forms produce
        // identical expansion.
        var cellEntries: [String] = []
        for member in classDecl.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
            let isState = varDecl.attributes.contains { attr in
                guard let attrSyntax = attr.as(AttributeSyntax.self),
                      let attrName = attrSyntax.attributeName.as(IdentifierTypeSyntax.self)?.name.text else {
                    return false
                }
                // @Persisted members are state cells too — same didSet shape,
                // same HMR snapshot/restore contract (hydration re-runs from
                // the store on remount, but a hot swap preserves the live
                // value like any @State).
                return attrName == "MacroState" || attrName == "State" || attrName == "Persisted"
            }
            guard isState else { continue }
            // Multi-binding @State is rejected by StateMacro's own diagnostic;
            // emit no cell for the invalid declaration.
            guard varDecl.bindings.count == 1 else { continue }
            guard let binding = varDecl.bindings.first,
                  let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier,
                  let typeAnno = binding.typeAnnotation else {
                continue   // diagnosed by @MacroState's own expansion
            }
            let name = identifier.text
            let valueType = typeAnno.type.trimmedDescription
            let isOptional = Self.isOptionalType(typeAnno.type)

            // Guardrail: a non-optional @State with no default, when @Component
            // owns construction, leaves the property uninitialized in the
            // synthesized init() — which the compiler reports as "return from
            // initializer without initializing all stored properties" on
            // invisible synthesized code. Diagnose at the property instead.
            // (@Persisted always carries a default; @MutationState/@ReducerState
            // are default-constructed in the synthesized init — this is @State
            // only. Optionals default to nil, so they need no explicit default.)
            let isPlainState = varDecl.attributes.contains { attr in
                guard let a = attr.as(AttributeSyntax.self),
                      let n = a.attributeName.as(IdentifierTypeSyntax.self)?.name.text else { return false }
                return n == "State" || n == "MacroState"
            }
            if isPlainState, !hasUserInit, !isOptional, binding.initializer == nil {
                context.diagnose(Diagnostic(
                    node: Syntax(varDecl),
                    message: ComponentMacroDiagnostic.stateNeedsDefault(name: name, type: valueType)
                ))
            }

            // Per Phase 15 Task 1 finding: Optional<T>.none stored in Any
            // is type-erased. Snapshot must normalize .none to HMRNilSentinel
            // at the source so the encoder never sees a raw nil-Optional.
            //
            // `_hmrCoerce` provides the Int↔Double bridge-round-trip
            // coercion the old `State<T>` propertyWrapper class did
            // inline; lives in `StateCell.swift` (public so macro-emitted
            // code in user modules can reach it).
            if isOptional {
                cellEntries.append("""
                    StateCell<\(className)>(
                        name: "\(name)",
                        snapshot: { c in
                            c.\(name).map { $0 as Any } ?? HMRNilSentinel() as Any
                        },
                        restore: { c, v in
                            guard let typed = _hmrCoerce(v, to: \(valueType).self) else {
                                return false
                            }
                            c.\(name) = typed
                            return true
                        },
                        restoreNil: { c in
                            c.\(name) = nil
                            return true
                        }
                    )
                    """)
            } else {
                cellEntries.append("""
                    StateCell<\(className)>(
                        name: "\(name)",
                        snapshot: {
                            $0.\(name) as Any
                        },
                        restore: { c, v in
                            guard let typed = _hmrCoerce(v, to: \(valueType).self) else {
                                return false
                            }
                            c.\(name) = typed
                            return true
                        },
                        restoreNil: { _ in
                            false
                        }
                    )
                    """)
            }
        }

        let stateCellsDecl: DeclSyntax
        if cellEntries.isEmpty {
            stateCellsDecl = DeclSyntax(stringLiteral: "@MainActor \(access)static let stateCells: [any AnyStateCell] = []")
        } else {
            let joined = cellEntries.joined(separator: ",\n    ")
            let body = "[\n    \(joined),\n]"
            stateCellsDecl = DeclSyntax(stringLiteral: "@MainActor \(access)static let stateCells: [any AnyStateCell] = \(body)")
        }

        // Collect @MutationState property names so `bind` can wire each
        // runtime's QueryClient at mount (spec §8, B1). Alongside, record each
        // mutation's type for the synthesized memberwise init (catalogue #1):
        // a component whose mutations are all default-constructible no longer
        // hand-writes `init() { self.add = AddTodo() }`.
        var mutationNames: [String] = []
        var mutationInits: [(name: String, type: String)] = []
        for member in classDecl.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
            let isMutation = varDecl.attributes.contains { attr in
                guard let a = attr.as(AttributeSyntax.self),
                      let n = a.attributeName.as(IdentifierTypeSyntax.self)?.name.text else { return false }
                return n == "MutationState"
            }
            guard isMutation,
                  // Multi-binding is rejected by MutationStateMacro (no runtime
                  // is emitted) — skip so bind/init don't reference a missing
                  // `_name_mutationRuntime`.
                  varDecl.bindings.count == 1,
                  let b = varDecl.bindings.first,
                  let id = b.pattern.as(IdentifierPatternSyntax.self)?.identifier else { continue }
            mutationNames.append(id.text)
            // A mutation with an inline default initializes itself; one without
            // (the common case) needs assignment in the synthesized init.
            if b.initializer == nil, let type = b.typeAnnotation?.type.trimmedDescription {
                mutationInits.append((id.text, type))
            }
        }

        // Parallel scan for @ReducerState — collect names for bind wiring and
        // types for the synthesized init (mirrors the @MutationState scan above).
        var reducerNames: [String] = []
        var reducerInits: [(name: String, type: String)] = []
        for member in classDecl.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
            let isReducer = varDecl.attributes.contains { attr in
                guard let a = attr.as(AttributeSyntax.self),
                      let n = a.attributeName.as(IdentifierTypeSyntax.self)?.name.text else { return false }
                return n == "ReducerState"
            }
            guard isReducer,
                  // Mirror of the @MutationState multi-binding skip above.
                  varDecl.bindings.count == 1,
                  let b = varDecl.bindings.first,
                  let id = b.pattern.as(IdentifierPatternSyntax.self)?.identifier else { continue }
            reducerNames.append(id.text)
            if b.initializer == nil, let type = b.typeAnnotation?.type.trimmedDescription {
                reducerInits.append((id.text, type))
            }
        }

        // Scan for @Persisted — collect (name, type, explicit-key) so the
        // hydration wiring below can be synthesized. Key derivation shares
        // PersistedKeyDerivation with PersistedMacro's didSet so the two
        // emission sites cannot drift.
        var persistedMembers: [(name: String, valueType: String, explicitKey: String?)] = []
        for member in classDecl.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
            var persistedAttr: AttributeSyntax? = nil
            for attr in varDecl.attributes {
                if let a = attr.as(AttributeSyntax.self),
                   a.attributeName.as(IdentifierTypeSyntax.self)?.name.text == "Persisted" {
                    persistedAttr = a
                    break
                }
            }
            guard let persistedAttr,
                  // Multi-binding / missing type: PersistedMacro diagnoses;
                  // emit no hydration for the invalid declaration.
                  varDecl.bindings.count == 1,
                  let b = varDecl.bindings.first,
                  let id = b.pattern.as(IdentifierPatternSyntax.self)?.identifier,
                  let typeAnno = b.typeAnnotation else { continue }
            guard !PersistedKeyDerivation.hasNonLiteralKey(persistedAttr) else { continue }
            persistedMembers.append((
                name: id.text,
                valueType: typeAnno.type.trimmedDescription,
                explicitKey: PersistedKeyDerivation.explicitKey(from: persistedAttr)
            ))
        }

        // Build the `bind` body: always the two owner/scheduler assignments,
        // plus one wire() line per @MutationState (conditional — mutation-free
        // components emit a byte-identical body with no SwiflowQuery reference),
        // then one wire() line per @ReducerState.
        var bindStmts = ["self._swiflowOwner = owner", "self._swiflowScheduler = scheduler"]
        bindStmts += mutationNames.map { name in
            "_\(name)_mutationRuntime.wire(owner: owner, scheduler: scheduler, client: _currentRenderQueryClient())"
        }
        bindStmts += reducerNames.map { name in
            "_\(name)_reducerRuntime.wire(owner: owner, scheduler: scheduler)"
        }
        let bindBody = bindStmts.joined(separator: "\n    ")
        let bindDecl = DeclSyntax(stringLiteral: "\(synthActor)\(access)func bind(owner: AnyComponent, scheduler: Scheduler) {\n    \(bindBody)\n}")

        // Synthesize a zero-arg `init()` when the class declares none.
        //
        // For bare `@Component` (synthActor != ""), we ALWAYS synthesize a
        // `@MainActor init()` — even for mutation-free components — because
        // the synthesized storage (`_swiflowOwner`, `_swiflowScheduler`) is
        // `@MainActor`-isolated. Without an explicit `@MainActor init()`,
        // Swift generates a nonisolated default init which conflicts with those
        // `@MainActor`-isolated stored properties (Swift 6 strict concurrency).
        //
        // When the type already carries explicit `@MainActor` (`synthActor == ""`),
        // Swift itself infers the correct actor on the implicit default init, so
        // we revert to the old behaviour: synthesize only when mutations/reducers
        // require default-construction assignments.
        let allInits = mutationInits + reducerInits
        var synthesizedInit: DeclSyntax? = nil
        if !hasUserInit {
            if !allInits.isEmpty {
                let assignments = allInits
                    .map { "    self.\($0.name) = \($0.type)()" }
                    .joined(separator: "\n")
                synthesizedInit = DeclSyntax(stringLiteral: "\(synthActor)\(access)init() {\n\(assignments)\n}")
            } else if !synthActor.isEmpty {
                // Bare @Component with no mutations/reducers: emit an empty
                // @MainActor init() to avoid the nonisolated-default-init conflict.
                synthesizedInit = DeclSyntax(stringLiteral: "\(synthActor)\(access)init() {}")
            }
        }

        // The init leads the emitted members (constructor first), followed by
        // the runtime plumbing.
        var emitted: [DeclSyntax] = []
        if let synthesizedInit { emitted.append(synthesizedInit) }
        emitted.append(contentsOf: [
            DeclSyntax(stringLiteral: "\(synthActor)private weak var _swiflowOwner: AnyComponent?"),
            DeclSyntax(stringLiteral: "\(synthActor)private var _swiflowScheduler: Scheduler?"),
            stateCellsDecl,
            bindDecl,
        ])

        // @Persisted hydration wiring — ONLY when such members exist, so a
        // persistence-free component's emission stays byte-identical (the
        // existing goldens pin that). The flag window around each assignment
        // is SYNCHRONOUS (no await between set/assign/clear): a user write
        // can never interleave and have its save flag-swallowed. The mount
        // hook is the Component._swiflowDidMount requirement the diff fires
        // before onAppear.
        if !persistedMembers.isEmpty {
            let hydrateBlocks = persistedMembers.map { m in
                let key = PersistedKeyDerivation.keyExpression(
                    explicitKey: m.explicitKey, propertyName: m.name)
                return """
                    if let v = try? await _PersistedStorageRegistry.current.load(\(m.valueType).self, forKey: \(key)) {
                        _swiflowIsHydrating = true
                        \(m.name) = v
                        _swiflowIsHydrating = false
                    }
                """
            }.joined(separator: "\n")
            emitted.append(contentsOf: [
                DeclSyntax(stringLiteral:
                    "\(access)static let _swiflowPersistNamespace = \"\(className)\""),
                DeclSyntax(stringLiteral:
                    "\(synthActor)var _swiflowIsHydrating = false"),
                DeclSyntax(stringLiteral:
                    "\(synthActor)\(access)func _swiflowDidMount() {\n    Task { await self._swiflowHydratePersisted() }\n}"),
                DeclSyntax(stringLiteral:
                    "\(synthActor)\(access)func _swiflowHydratePersisted() async {\n\(hydrateBlocks)\n}"),
            ])
        }
        return emitted
    }

    // MARK: - Helpers

    /// Optionality by SYNTAX, not by string suffix: `Int?` is
    /// `OptionalTypeSyntax`; the long spellings `Optional<Int>` and
    /// `Swift.Optional<Int>` are identifier/member types named "Optional"
    /// with a generic argument. (The audit found `hasSuffix("?")` silently
    /// mis-classified the long spelling, skipping HMRNilSentinel
    /// normalization.)
    static func isOptionalType(_ type: TypeSyntax) -> Bool {
        if type.is(OptionalTypeSyntax.self) { return true }
        if let ident = type.as(IdentifierTypeSyntax.self),
           ident.name.text == "Optional",
           ident.genericArgumentClause != nil {
            return true
        }
        if let member = type.as(MemberTypeSyntax.self),
           member.name.text == "Optional",
           member.genericArgumentClause != nil {
            return true
        }
        return false
    }
}

extension ComponentMacro: MemberAttributeMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingAttributesFor member: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AttributeSyntax] {
        guard let classDecl = declaration.as(ClassDeclSyntax.self),
              classDecl.modifiers.contains(where: { $0.name.text == "final" }) else {
            return []   // non-final / non-class: diagnosed by the other roles
        }
        // Whole-type skip: an explicitly-isolated component keeps today's exact
        // expansion (and avoids a redundant-attribute diagnostic).
        if ComponentIsolation.hasMainActorAttribute(classDecl.attributes) { return [] }
        return ComponentIsolation.attributes(for: member)
    }
}

enum ComponentMacroDiagnostic: DiagnosticMessage {
    case requiresClass
    case requiresFinal
    case stateNeedsDefault(name: String, type: String)

    var message: String {
        switch self {
        case .requiresClass:
            return "@Component requires a class — components are reference types in Swiflow"
        case .requiresFinal:
            return "@Component requires 'final' — components cannot be subclassed"
        case let .stateNeedsDefault(name, type):
            return "@State '\(name)' needs a default value — @Component synthesizes init(), so give it one (e.g. `@State var \(name): \(type) = …`), or write your own init that assigns it."
        }
    }

    var diagnosticID: MessageID {
        let id: String
        switch self {
        case .requiresClass: id = "requiresClass"
        case .requiresFinal: id = "requiresFinal"
        case .stateNeedsDefault: id = "stateNeedsDefault"
        }
        return MessageID(domain: "SwiflowMacros", id: id)
    }

    var severity: DiagnosticSeverity { .error }
}
