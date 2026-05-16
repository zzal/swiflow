// Sources/Swiflow/DSL/RawHTML.swift

/// Renders unescaped HTML via the DOM's `innerHTML` setter. Use this only
/// when the markup is trusted (constants, server-sanitized input, …).
///
/// The name is intentional: `git grep "rawHTML("` enumerates every audit
/// site in a project. There is no shorter alias.
public func rawHTML(_ html: String) -> VNode {
    .rawHTML(html)
}
