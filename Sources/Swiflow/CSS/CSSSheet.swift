public struct CSSSheet: Sendable {
    package let entries: [CSSEntry]

    public init(entries: [CSSEntry]) {
        self.entries = entries
    }

    public func cssString(scopeClass: String) -> String {
        entries.map { $0.cssString(scopeClass: scopeClass) }.joined(separator: "\n")
    }
}

public enum CSSEntry: Sendable {
    case rule(selector: String, declarations: [CSSDeclaration])
    case keyframes(name: String, stops: [KeyframeStop])
    case host(declarations: [CSSDeclaration])
    /// A conditional at-rule (`@container`, `@media`, …) wrapping nested
    /// entries. `prefix` is the full at-rule header (e.g. `@container (max-width: 380px)`);
    /// the nested entries are scoped with the same `scopeClass` and indented,
    /// so the wrapper participates in scoping instead of reaching around it.
    case group(prefix: String, entries: [CSSEntry])
    case raw(String)
    /// CSS authored via `#css`. Rendered as `.<scopeClass> { <body> }` so the
    /// browser's native CSS nesting performs the scoping; the body is passed
    /// to the browser verbatim. See docs/superpowers/specs/2026-06-12-css-macro-design.md.
    ///
    /// Deliberately has no `CSSBuilder` free function: it is the `#css`
    /// macro's expansion target, and the macro's compile-time validation is
    /// the only supported way to author one. Hand-written raw CSS goes
    /// through `raw(_:)`.
    case scopedBlock(String)

    package func cssString(scopeClass: String) -> String {
        switch self {
        case .rule(let selector, let declarations):
            // A selector LIST scopes per part — `.a, .b` must scope BOTH `.a`
            // and `.b`, or everything after the first comma leaks as a global
            // rule and silently defeats per-component isolation. Commas inside
            // `:is(...)`/`[attr="a,b"]` don't split (see splitTopLevelCommas).
            let effectiveSelector = Self.splitTopLevelCommas(selector)
                .map { scopedSelector($0, scopeClass: scopeClass) }
                .joined(separator: ", ")
            let decls = declarations.map { "  \($0.name): \($0.value);" }.joined(separator: "\n")
            return "\(effectiveSelector) {\n\(decls)\n}"
        case .keyframes(let name, let stops):
            let stopsStr = stops.map { stop -> String in
                let decls = stop.declarations.map { "    \($0.name): \($0.value);" }.joined(separator: "\n")
                return "  \(stop.position) {\n\(decls)\n  }"
            }.joined(separator: "\n")
            return "@keyframes \(name) {\n\(stopsStr)\n}"
        case .host(let declarations):
            let decls = declarations.map { "  \($0.name): \($0.value);" }.joined(separator: "\n")
            return ".\(scopeClass) {\n\(decls)\n}"
        case .group(let prefix, let entries):
            // Render nested entries with the same scope, then indent one level
            // and wrap in the at-rule. Blank lines stay blank (no trailing space).
            let body = entries.map { $0.cssString(scopeClass: scopeClass) }.joined(separator: "\n")
            return "\(prefix) {\n\(Self.indentOneLevel(body))\n}"
        case .raw(let text):
            return text
        case .scopedBlock(let body):
            return ".\(scopeClass) {\n\(Self.indentOneLevel(body))\n}"
        }
    }

    /// Indents every non-empty line by one level (two spaces). Blank lines
    /// stay blank so no trailing whitespace is introduced.
    private static func indentOneLevel(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.isEmpty ? "" : "  " + $0 }
            .joined(separator: "\n")
    }

    private func shouldScope(_ selector: String) -> Bool {
        let lower = selector.lowercased()
        return !(lower.hasPrefix(":root") || lower.hasPrefix("html") || lower.hasPrefix("body"))
    }

    /// One (already comma-split) selector's scoped form:
    /// - unscopeable (`:root`/`html`/`body`) → verbatim;
    /// - class-leading → the compound form (matches the scope-class root
    ///   element when it carries this class) PLUS the descendant form
    ///   (matches nested elements);
    /// - anything else → descendant form only.
    private func scopedSelector(_ selector: String, scopeClass: String) -> String {
        guard shouldScope(selector) else { return selector }
        if selector.hasPrefix(".") {
            return ".\(scopeClass)\(selector), .\(scopeClass) \(selector)"
        }
        return ".\(scopeClass) \(selector)"
    }

    /// Split a selector list on top-level commas. Commas inside parentheses
    /// (`:is(.a, .b)`), brackets, or quoted strings (`[data-x="a,b"]`) do NOT
    /// split. Parts are whitespace-trimmed; empty parts are dropped. Escaped
    /// characters in identifiers (`\,`) are not handled — vanishingly rare in
    /// class names and unsupported by the structural `#css` parser anyway.
    static func splitTopLevelCommas(_ selector: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = 0
        var quote: Character? = nil
        for ch in selector {
            if let q = quote {
                current.append(ch)
                if ch == q { quote = nil }
                continue
            }
            switch ch {
            case "\"", "'":
                quote = ch
                current.append(ch)
            case "(", "[":
                depth += 1
                current.append(ch)
            case ")", "]":
                depth -= 1
                current.append(ch)
            case "," where depth == 0:
                parts.append(Self.trimmed(current))
                current = ""
            default:
                current.append(ch)
            }
        }
        parts.append(Self.trimmed(current))
        return parts.filter { !$0.isEmpty }
    }

    /// Foundation-free whitespace trim (core Swiflow avoids Foundation).
    private static func trimmed(_ s: String) -> String {
        var sub = Substring(s)
        while sub.first?.isWhitespace == true { sub.removeFirst() }
        while sub.last?.isWhitespace == true { sub.removeLast() }
        return String(sub)
    }
}

public struct CSSDeclaration: Sendable {
    package let name: String
    package let value: String

    package init(_ name: String, _ value: String) {
        self.name = name
        self.value = value
    }
}

public struct KeyframeStop: Sendable {
    package let position: String  // "from", "to", or "50%"
    package let declarations: [CSSDeclaration]
}
