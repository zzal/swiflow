// Sources/SwiflowRouter/Core/LinkActiveMatch.swift
//
// How a Link decides it points at the CURRENT route (audit IV Wave-1 #2).
// Lives in Core — the matcher is pure and host-tested, and keeping it out
// of the browser layer mirrors RouterMode's placement.

/// Matching rule for a `Link`'s active state (`aria-current="page"` +
/// `.sw-link-active`).
///
/// - `.exact` (the default): active only when the router's path equals the
///   link's destination.
/// - `.prefix`: also active on segment CHILDREN of the destination —
///   `/users` lights up on `/users/42` — the usual choice for section
///   navs. Segment-aware: `/users` does NOT match `/users2`. On the root
///   path `/` it degrades to exact (every path is lexically under `/`,
///   and a Home link that lights up on every page marks nothing).
public enum LinkActiveMatch: Sendable, Equatable {
    case exact
    case prefix

    /// Pure matcher — the whole active-state decision, unit-tested directly.
    public func isActive(linkPath: String, currentPath: String) -> Bool {
        switch self {
        case .exact:
            return currentPath == linkPath
        case .prefix:
            return currentPath == linkPath || currentPath.hasPrefix(linkPath + "/")
        }
    }
}
