// Sources/SwiflowRouter/Core/RouteTableHazards.swift
import Swiflow

/// DEBUG guardrail (audit IV Wave-3): walk a route table and warn about
/// sibling routes that can never match. `matchRoutes` is first-wins among
/// siblings (locked by test), so a later sibling with the same matching
/// SHAPE — or any sibling after a catch-all — is silently dead.
///
/// Called once from `RouterRoot`'s designated init; also directly testable.
/// Warns, never traps: a shadowed route renders the app fine, the developer
/// just meant something else ([[swiflowWarn]]'s charter).
@MainActor
package func warnRouteTableHazards(_ routes: [RouteDefinition]) {
    var firstSeen: [String: String] = [:]   // shapeKey → original pattern
    for (index, route) in routes.enumerated() {
        let shape = route.pattern.shapeKey
        if let earlier = firstSeen[shape] {
            swiflowWarn(
                "Route '\(route.pattern.original)' duplicates the shape of the earlier "
                    + "sibling '\(earlier)' — sibling matching is first-wins, so this "
                    + "route can never match. Remove one, or reorder if the shapes "
                    + "were meant to differ."
            )
        } else {
            firstSeen[shape] = route.pattern.original
        }
        if shape == "*" && index < routes.count - 1 {
            swiflowWarn(
                "Route '\(route.pattern.original)' is a catch-all placed before "
                    + "\(routes.count - 1 - index) sibling route(s) — they can never "
                    + "match. Move the catch-all last."
            )
        }
        warnRouteTableHazards(route.children)
    }
}
