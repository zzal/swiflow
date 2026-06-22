// Sources/SwiflowMacrosPlugin/SynthesizedAccess.swift
import SwiftSyntax

/// The access-level keyword a synthesized witness / initializer must carry so it
/// is reachable wherever the host type is.
///
/// Swift's *free* memberwise init is always `internal`, and a macro-emitted
/// protocol witness defaults to `internal` too. On a `public` or `package` host
/// that silently narrows the synthesized member below the type — a cross-module
/// break surfacing as a misleading "inaccessible due to '…' protection level"
/// error at the *call* site. So every macro that emits members
/// (`@Component` / `@QueryType` / `@MutationType`) copies the host type's access
/// onto what it emits, through this one helper.
///
/// The result is a trailing-space-terminated keyword for direct interpolation
/// (`"\(access)init(...)"`):
/// - `public` / `open` host → `"public "`. A synthesized initializer or protocol
///   witness is never `open` — `open` only governs subclassing/overriding, which
///   these aren't — so it collapses to `public`.
/// - `package` host → `"package "`.
/// - `internal` / `fileprivate` / `private` / no modifier → `""`. The default
///   already covers `internal`; for the more-restrictive levels an explicit
///   broader keyword would only be capped by the compiler, so emitting nothing
///   is both correct and matches the type's effective visibility.
enum SynthesizedAccess {
    static func keyword(for modifiers: DeclModifierListSyntax) -> String {
        for modifier in modifiers {
            switch modifier.name.tokenKind {
            case .keyword(.public), .keyword(.open):
                return "public "
            case .keyword(.package):
                return "package "
            default:
                continue
            }
        }
        return ""
    }
}
