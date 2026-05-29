public struct CSSSheet: Sendable {
    package let entries: [CSSEntry]

    package init(entries: [CSSEntry]) {
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
    case raw(String)

    package func cssString(scopeClass: String) -> String {
        switch self {
        case .rule(let selector, let declarations):
            let effectiveSelector: String
            if !shouldScope(selector) {
                effectiveSelector = selector
        // TODO: Comma-separated selector lists (e.g. ".a, .b") are not split here;
        // only the first selector token gets the dual treatment, the rest are
        // emitted as-is and end up unscoped. Add a list-splitter when this surfaces.
            } else if selector.hasPrefix(".") {
                // Class-leading selector: emit both the compound form (matches the
                // scope-class root element when it carries this class) and the
                // descendant form (matches nested elements).
                let compound = ".\(scopeClass)\(selector)"
                let descendant = ".\(scopeClass) \(selector)"
                effectiveSelector = "\(compound), \(descendant)"
            } else {
                effectiveSelector = ".\(scopeClass) \(selector)"
            }
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
        case .raw(let text):
            return text
        }
    }

    private func shouldScope(_ selector: String) -> Bool {
        let lower = selector.lowercased()
        return !(lower.hasPrefix(":root") || lower.hasPrefix("html") || lower.hasPrefix("body"))
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
