// Sources/SwiflowMacrosPlugin/InitSynthesis.swift
import SwiftSyntax

/// Shared memberwise-initializer synthesis for `@QueryType` / `@MutationType`.
/// A pure syntax → syntax transform: no diagnostics, no expansion context.
///
/// Rules (spike §3.2):
/// - One parameter per stored property **that carries an explicit type
///   annotation**, in source order, copying the property's default-value
///   expression as the parameter default — that's the test seam, e.g.
///   `api: FakeAPI = FakeAPI()`.
/// - A stored property with **no** type annotation can't be named as a parameter,
///   so it is initialized from its own inline default and omitted (not
///   injectable). `@QueryType` separately requires `@Key`s to be annotated.
/// - `static`/`class` and computed/observed members are skipped — only instance
///   storage is initialized.
/// - The init's access level matches the host (`isPublic` → `public init`), so a
///   `public` query/mutation gets a `public` initializer (Swift's free memberwise
///   init is only `internal`).
/// - Returns `nil` when the struct already declares any initializer — the user
///   owns construction, mirroring Swift's own memberwise-init suppression.
enum InitSynthesis {
    static func memberwiseInit(for structDecl: StructDeclSyntax, isPublic: Bool) -> DeclSyntax? {
        // Any user-written init suppresses synthesis entirely.
        let hasUserInit = structDecl.memberBlock.members.contains { $0.decl.is(InitializerDeclSyntax.self) }
        if hasUserInit { return nil }

        var params: [String] = []
        var assignments: [String] = []

        for member in structDecl.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
            // Type-level storage isn't an instance member.
            let isTypeLevel = varDecl.modifiers.contains {
                $0.name.tokenKind == .keyword(.static) || $0.name.tokenKind == .keyword(.class)
            }
            if isTypeLevel { continue }

            for binding in varDecl.bindings {
                // A stored property has no accessor block; a computed property
                // (getter) or an observed one (didSet/willSet) does — skip those.
                guard binding.accessorBlock == nil,
                      let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text
                else { continue }

                // Without an annotation we can't name the parameter's type, so the
                // property keeps its inline default and is left out of the init.
                guard let type = binding.typeAnnotation?.type.trimmedDescription else { continue }

                if let defaultValue = binding.initializer?.value.trimmedDescription {
                    params.append("\(name): \(type) = \(defaultValue)")
                } else {
                    params.append("\(name): \(type)")
                }
                assignments.append("    self.\(name) = \(name)")
            }
        }

        let access = isPublic ? "public " : ""
        let paramList = params.joined(separator: ", ")
        let body = assignments.isEmpty ? "" : "\n" + assignments.joined(separator: "\n") + "\n"
        return DeclSyntax(stringLiteral: "\(access)init(\(paramList)) {\(body)}")
    }
}
