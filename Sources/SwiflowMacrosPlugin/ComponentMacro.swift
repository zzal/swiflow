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

        // Detect class access level so the emitted protocol witnesses match
        // the host class's visibility. A public class adopting the public
        // `_ComponentRuntime` protocol must declare its witnesses public.
        // Internal/private/fileprivate classes don't get a leading keyword
        // (the default access already covers internal). The `runtimeOwner`
        // and `runtimeScheduler` stored properties stay private regardless
        // — they're implementation detail, not part of the protocol.
        let isPublic = classDecl.modifiers.contains { mod in
            mod.name.tokenKind == .keyword(.public) ||
            mod.name.tokenKind == .keyword(.open)
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
                return attrName == "MacroState" || attrName == "State"
            }
            guard isState else { continue }
            guard let binding = varDecl.bindings.first,
                  let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier,
                  let typeAnno = binding.typeAnnotation else {
                continue   // diagnosed by @MacroState's own expansion
            }
            let name = identifier.text
            let valueType = typeAnno.type.trimmedDescription
            let isOptional = valueType.hasSuffix("?")

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
            if isPublic {
                stateCellsDecl = "@MainActor public static let stateCells: [any AnyStateCell] = []"
            } else {
                stateCellsDecl = "@MainActor static let stateCells: [any AnyStateCell] = []"
            }
        } else {
            let joined = cellEntries.joined(separator: ",\n    ")
            let body = "[\n    \(joined),\n]"
            if isPublic {
                stateCellsDecl = DeclSyntax(stringLiteral: "@MainActor public static let stateCells: [any AnyStateCell] = \(body)")
            } else {
                stateCellsDecl = DeclSyntax(stringLiteral: "@MainActor static let stateCells: [any AnyStateCell] = \(body)")
            }
        }

        let bindDecl: DeclSyntax = isPublic
            ? """
              public func bind(owner: AnyComponent, scheduler: Scheduler) {
                  self.runtimeOwner = owner
                  self.runtimeScheduler = scheduler
              }
              """
            : """
              func bind(owner: AnyComponent, scheduler: Scheduler) {
                  self.runtimeOwner = owner
                  self.runtimeScheduler = scheduler
              }
              """

        return [
            "private weak var runtimeOwner: AnyComponent?",
            "private var runtimeScheduler: Scheduler?",
            stateCellsDecl,
            bindDecl,
        ]
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
