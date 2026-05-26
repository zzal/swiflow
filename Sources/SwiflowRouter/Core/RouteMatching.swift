// Sources/SwiflowRouter/Core/RouteMatching.swift
import Foundation
import Swiflow

/// Walks `routes` depth-first, returns the first matching route's VNode.
/// Strips the query string before pattern matching; parsed query params
/// are available in `RouterContext.query`. Returns `nil` if no route matches.
@MainActor
package func matchRoutes(_ routes: [RouteDefinition], path: String) -> VNode? {
    let (cleanPath, query) = splitQuery(path)
    return matchList(routes, path: cleanPath, parentParams: [:], query: query)
}

// MARK: - Private helpers

@MainActor
private func matchList(
    _ routes: [RouteDefinition],
    path: String,
    parentParams: [String: String],
    query: [String: String]
) -> VNode? {
    for route in routes {
        if route.children.isEmpty {
            // Leaf: attempt full match
            if let params = route.pattern.match(path) {
                let merged = parentParams.merging(params) { _, new in new }
                let ctx = RouterContext(path: path, params: merged, query: query)
                return route.factory(ctx)
            }
        } else {
            // Namespace: attempt prefix match, recurse into children
            if let (remainder, params) = route.pattern.prefixMatch(path) {
                let merged = parentParams.merging(params) { _, new in new }
                if let result = matchList(route.children, path: remainder, parentParams: merged, query: query) {
                    return result
                }
            }
        }
    }
    return nil
}

private func splitQuery(_ path: String) -> (clean: String, query: [String: String]) {
    guard let qIdx = path.firstIndex(of: "?") else { return (path, [:]) }
    let clean = String(path[path.startIndex..<qIdx])
    let queryString = String(path[path.index(after: qIdx)...])
    var query: [String: String] = [:]
    for pair in queryString.split(separator: "&") {
        let parts = pair.split(separator: "=", maxSplits: 1)
        if parts.count == 2 {
            let key = String(parts[0]).removingPercentEncoding ?? String(parts[0])
            let value = String(parts[1]).removingPercentEncoding ?? String(parts[1])
            query[key] = value
        }
    }
    return (clean, query)
}
