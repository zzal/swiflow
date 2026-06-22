// Sources/SwiflowMacrosPlugin/QueryTypeMacro.swift
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// `@QueryType` synthesizes `Query` conformance for a struct: it derives
/// `queryKey` from the `@Key` stored properties (in source order, prefixed by the
/// type name or a custom `prefix:`) and reuses `InitSynthesis` for the memberwise
/// initializer (the test seam). `fetch()` is always hand-written. A hand-written
/// `queryKey` or `init` is never fought.
public struct QueryTypeMacro: ExtensionMacro, MemberMacro {

    // MARK: ExtensionMacro

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard declaration.is(StructDeclSyntax.self) else {
            context.diagnose(Diagnostic(
                node: nonStructKeyword(declaration),
                message: QueryTypeDiagnostic.requiresStruct))
            return []
        }
        // Respect `conformingTo`: emit only the conformances still missing, so a
        // migration `@QueryType struct Foo: Query` doesn't double-conform. (Unlike
        // @Component — whose conformances are private runtime contracts — `Query`
        // is a public protocol a user may already have declared by hand.)
        guard !protocols.isEmpty else { return [] }
        let list = protocols.map { $0.trimmedDescription }.joined(separator: ", ")
        return [try ExtensionDeclSyntax("extension \(type): \(raw: list) {}")]
    }

    // MARK: MemberMacro

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            return []   // non-struct already diagnosed in the extension path
        }
        let access = SynthesizedAccess.keyword(for: structDecl.modifiers)

        var members: [DeclSyntax] = []

        // queryKey — unless the user wrote their own.
        if !structDecl.declaresQueryKey {
            let prefix = prefixArgument(from: node, in: context) ?? structDecl.name.text
            let keyExprs = keyExpressions(in: structDecl, context: context)
            let rhs = (["[\"\(prefix)\"]"] + keyExprs).joined(separator: " + ")
            members.append("\(raw: access)var queryKey: QueryKey {\n    \(raw: rhs)\n}")
        }

        // Memberwise init — unless the user wrote their own (InitSynthesis returns nil).
        if let initDecl = InitSynthesis.memberwiseInit(for: structDecl, access: access) {
            members.append(initDecl)
        }

        return members
    }

    // MARK: - Helpers

    /// `_qkc(name)` for each `@Key` stored property in source order. Diagnoses an
    /// unannotated `@Key` (it would be omitted from the init, so the key couldn't
    /// vary across tests) and skips it.
    private static func keyExpressions(
        in structDecl: StructDeclSyntax,
        context: some MacroExpansionContext
    ) -> [String] {
        var exprs: [String] = []
        for member in structDecl.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
            let isKey = varDecl.attributes.contains { attr in
                attr.as(AttributeSyntax.self)?
                    .attributeName.as(IdentifierTypeSyntax.self)?.name.text == "Key"
            }
            guard isKey else { continue }
            for binding in varDecl.bindings {
                guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else { continue }
                guard binding.typeAnnotation != nil else {
                    context.diagnose(Diagnostic(
                        node: Syntax(varDecl),
                        message: QueryTypeDiagnostic.keyNeedsType))
                    continue
                }
                exprs.append("_qkc(\(name))")
            }
        }
        return exprs
    }

    /// The `prefix:` argument value if present — requiring a single-segment string
    /// literal (the key prefix must be statically known); diagnoses otherwise.
    private static func prefixArgument(
        from node: AttributeSyntax,
        in context: some MacroExpansionContext
    ) -> String? {
        guard let args = node.arguments?.as(LabeledExprListSyntax.self),
              let prefixArg = args.first(where: { $0.label?.text == "prefix" }) else {
            return nil
        }
        guard let str = prefixArg.expression.as(StringLiteralExprSyntax.self),
              str.segments.count == 1,
              let seg = str.segments.first?.as(StringSegmentSyntax.self) else {
            context.diagnose(Diagnostic(
                node: Syntax(prefixArg.expression),
                message: QueryTypeDiagnostic.prefixMustBeLiteral))
            return nil
        }
        return seg.content.text
    }

    private static func nonStructKeyword(_ declaration: some DeclGroupSyntax) -> Syntax {
        if let c = declaration.as(ClassDeclSyntax.self) { return Syntax(c.classKeyword) }
        if let e = declaration.as(EnumDeclSyntax.self) { return Syntax(e.enumKeyword) }
        if let a = declaration.as(ActorDeclSyntax.self) { return Syntax(a.actorKeyword) }
        return Syntax(declaration)
    }
}

extension StructDeclSyntax {
    /// True if the struct already declares a `queryKey` property, so `@QueryType`
    /// leaves it alone.
    var declaresQueryKey: Bool {
        memberBlock.members.contains { member in
            guard let v = member.decl.as(VariableDeclSyntax.self) else { return false }
            return v.bindings.contains {
                $0.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == "queryKey"
            }
        }
    }
}

enum QueryTypeDiagnostic: DiagnosticMessage {
    case requiresStruct
    case prefixMustBeLiteral
    case keyNeedsType

    var message: String {
        switch self {
        case .requiresStruct:
            return "@QueryType requires a struct — queries are value types constructed every render."
        case .prefixMustBeLiteral:
            return "@QueryType(prefix:) requires a string literal — the key prefix must be statically known for the cache."
        case .keyNeedsType:
            return "@Key requires an explicit type annotation so the key can be injected in tests (e.g. @Key var id: Int)."
        }
    }
    var diagnosticID: MessageID { MessageID(domain: "SwiflowMacros", id: "\(self)") }
    var severity: DiagnosticSeverity { .error }
}

extension QueryTypeMacro: MemberAttributeMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingAttributesFor member: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AttributeSyntax] {
        guard declaration.is(StructDeclSyntax.self) else { return [] }
        return MainActorWitnessIsolation.attributes(for: member)
    }
}
