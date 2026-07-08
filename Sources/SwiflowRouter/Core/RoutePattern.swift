// Sources/SwiflowRouter/Core/RoutePattern.swift
import Swiflow

package struct RoutePattern: Sendable {
    private enum Segment: Sendable {
        case literal(String)
        case param(String)
        case wildcard
    }

    private let segments: [Segment]

    /// The original pattern string as passed to `init(_:)`, before
    /// normalisation. Useful for diagnostic output and test assertions.
    package let original: String

    package init(_ pattern: String) {
        original = pattern
        let stripped = Self.stripQuery(pattern)
        let normalized = stripped.hasSuffix("/") && stripped.count > 1
            ? String(stripped.dropLast())
            : stripped
        let withoutLeadingSlash = normalized.hasPrefix("/")
            ? String(normalized.dropFirst())
            : normalized
        if withoutLeadingSlash.isEmpty {
            segments = []
        } else {
            segments = withoutLeadingSlash
                .split(separator: "/", omittingEmptySubsequences: false)
                .map { part in
                    if part == "*" { return .wildcard }
                    if part.hasPrefix(":") { return .param(String(part.dropFirst())) }
                    return .literal(String(part))
                }
        }
        // Guardrail (audit IV Wave-3): a bare ":" segment silently captures
        // under the name "" — almost certainly a typo'd pattern.
        if segments.contains(where: { if case .param("") = $0 { return true }; return false }) {
            swiflowWarn(
                "Route pattern '\(pattern)' has an empty ':' parameter segment — "
                    + "it captures under the name \"\". Name the parameter "
                    + "(e.g. ':id') or drop the ':'."
            )
        }
    }

    /// The pattern's matching SHAPE, param names erased — two sibling
    /// patterns with the same shape match the same paths regardless of what
    /// their params are called (`/users/:id` vs `/users/:slug`). Powers the
    /// shadowed-sibling guardrail.
    package var shapeKey: String {
        segments.map { seg in
            switch seg {
            case .literal(let text): return text
            case .param: return ":"
            case .wildcard: return "*"
            }
        }.joined(separator: "/")
    }

    /// Full match: returns param dict on match, nil on no-match.
    /// Returns [:] for a static match with no params.
    package func match(_ path: String) -> [String: String]? {
        let parts = splitPath(normalize(path))
        return matchFull(segments, parts: parts)
    }

    /// Prefix match: returns (remainder, params) when this pattern matches
    /// a prefix of `path`. `remainder` is the unmatched suffix (always
    /// starts with `/`).
    package func prefixMatch(_ path: String) -> (remainder: String, params: [String: String])? {
        let parts = splitPath(normalize(path))
        guard let (params, remaining) = matchPrefix(segments, parts: parts) else { return nil }
        let remainder = remaining.isEmpty ? "/" : "/" + remaining.joined(separator: "/")
        return (remainder, params)
    }

    // MARK: - Private helpers

    private static func stripQuery(_ path: String) -> String {
        if let q = path.firstIndex(of: "?") { return String(path[path.startIndex..<q]) }
        return path
    }

    private func normalize(_ path: String) -> String {
        var s = Self.stripQuery(path)
        while s.hasSuffix("/") && s.count > 1 { s.removeLast() }
        if s.hasPrefix("/") { s = String(s.dropFirst()) }
        return s
    }

    private func splitPath(_ normalized: String) -> [String] {
        normalized.isEmpty ? [] : normalized.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    }

    private func matchFull(_ segs: [Segment], parts: [String]) -> [String: String]? {
        var params: [String: String] = [:]
        var i = 0
        for seg in segs {
            switch seg {
            case .literal(let expected):
                guard i < parts.count, parts[i] == expected else { return nil }
                i += 1
            case .param(let name):
                guard i < parts.count else { return nil }
                params[name] = percentDecode(parts[i]) ?? parts[i]
                i += 1
            case .wildcard:
                params["*"] = parts[i...].map { percentDecode($0) ?? $0 }.joined(separator: "/")
                i = parts.count
            }
        }
        guard i == parts.count else { return nil }
        return params
    }

    private func matchPrefix(_ segs: [Segment], parts: [String]) -> ([String: String], [String])? {
        var params: [String: String] = [:]
        var i = 0
        for seg in segs {
            switch seg {
            case .literal(let expected):
                guard i < parts.count, parts[i] == expected else { return nil }
                i += 1
            case .param(let name):
                guard i < parts.count else { return nil }
                params[name] = percentDecode(parts[i]) ?? parts[i]
                i += 1
            case .wildcard:
                params["*"] = parts[i...].map { percentDecode($0) ?? $0 }.joined(separator: "/")
                return (params, [])
            }
        }
        return (params, Array(parts[i...]))
    }
}
