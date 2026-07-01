// Sources/SwiflowMacrosPlugin/ComponentIsolation.swift
import SwiftSyntax
import SwiftSyntaxMacros

/// `@attached(memberAttribute)` logic for `@Component`.
///
/// `Component`/`_ComponentRuntime` are `@MainActor` protocols, but Swift does
/// NOT infer a protocol's global actor onto the primary type when conformance
/// is added by a generated extension (see `MainActorWitnessIsolation` for the
/// same problem in `@Query`/`@Mutation`). So `@Component` stamps `@MainActor`
/// onto the component's members itself — making a bare `@Component final class`
/// isolation-equivalent to `@MainActor @Component final class`.
///
/// Unlike `@Query`/`@Mutation` (value types crossing actors → witness-subset
/// isolation), a component is an inherently main-actor reference type, so ALL
/// members are isolated — faithfully mirroring `@MainActor class`.
enum ComponentIsolation {
    /// The attributes to add to one member. Skips what `@MainActor class` also
    /// leaves un-isolated (nested types, typealiases, deinit) and anything the
    /// author already isolated or opted out of with `nonisolated`.
    static func attributes(for member: some DeclSyntaxProtocol) -> [AttributeSyntax] {
        if member.is(StructDeclSyntax.self) || member.is(ClassDeclSyntax.self)
            || member.is(EnumDeclSyntax.self) || member.is(ActorDeclSyntax.self)
            || member.is(TypeAliasDeclSyntax.self) || member.is(DeinitializerDeclSyntax.self) {
            return []
        }
        if memberHasIsolation(member) { return [] }
        return ["@MainActor"]
    }

    /// True when the class carries an explicit `@MainActor` (detected by name).
    /// Used to skip auto-injection entirely so existing `@MainActor @Component`
    /// code expands byte-identically.
    static func hasMainActorAttribute(_ attributes: AttributeListSyntax) -> Bool {
        attributes.contains { element in
            guard case let .attribute(attr) = element else { return false }
            return attr.attributeName.trimmedDescription == "MainActor"
        }
    }

    private static func memberHasIsolation(_ member: some DeclSyntaxProtocol) -> Bool {
        if let mods = member.asProtocol(WithModifiersSyntax.self)?.modifiers,
           mods.contains(where: { $0.name.tokenKind == .keyword(.nonisolated) }) {
            return true
        }
        if let attrs = member.asProtocol(WithAttributesSyntax.self)?.attributes {
            return hasMainActorAttribute(attrs)
        }
        return false
    }
}
