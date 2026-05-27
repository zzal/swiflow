// Sources/SwiflowRouter/Core/RouteMatching.swift
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
            let key = percentDecode(String(parts[0])) ?? String(parts[0])
            let value = percentDecode(String(parts[1])) ?? String(parts[1])
            query[key] = value
        }
    }
    return (clean, query)
}

/// RFC 3986 percent-decoder for URL query keys and values.
///
/// Returns `nil` for any malformed `%XX` sequence or for byte sequences
/// that do not form valid UTF-8 — matches `String.removingPercentEncoding`
/// semantics exactly, so `splitQuery`'s `?? original` fallback preserves
/// the prior behavior on invalid input.
///
/// `+` is left as a literal `+` (RFC 3986 query semantics). WHATWG
/// URLSearchParams and HTML form encoding translate `+` to space — that
/// is a separate semantic choice tracked by the
/// `queryPlusStaysLiteral` regression test.
private func percentDecode(_ s: String) -> String? {
    guard s.contains("%") else { return s }     // fast path
    var bytes: [UInt8] = []
    bytes.reserveCapacity(s.utf8.count)
    var it = s.utf8.makeIterator()
    while let b = it.next() {
        if b == 0x25 {  // '%'
            guard let h1 = it.next(), let h2 = it.next(),
                  let hi = hexDigit(h1), let lo = hexDigit(h2)
            else { return nil }
            bytes.append((hi << 4) | lo)
        } else {
            bytes.append(b)
        }
    }
    // Validate UTF-8 strictly: `String(validating:as:)` would do this
    // in one call, but it's gated on macOS 15+ and the package targets
    // macOS 14. `Unicode.UTF8.ForwardParser` is stdlib, has no platform
    // gate, and gives the same nil-on-invalid semantics.
    var validator = Unicode.UTF8.ForwardParser()
    var byteIter = bytes.makeIterator()
    while true {
        switch validator.parseScalar(from: &byteIter) {
        case .valid: continue
        case .emptyInput:
            return String(decoding: bytes, as: UTF8.self)
        case .error:
            return nil
        }
    }
}

/// ASCII hex-digit nibble. `nil` for any non-hex byte.
/// `&+` is overflow-trapping arithmetic disabled: the case ranges
/// pre-validate the inputs, so overflow is impossible by construction.
private func hexDigit(_ b: UInt8) -> UInt8? {
    switch b {
    case 0x30...0x39: return b - 0x30           // '0'-'9'
    case 0x41...0x46: return b - 0x41 &+ 10     // 'A'-'F'
    case 0x61...0x66: return b - 0x61 &+ 10     // 'a'-'f'
    default: return nil
    }
}
