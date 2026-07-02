@resultBuilder
public struct CSSSheetBuilder {
    public static func buildBlock(_ entries: [CSSEntry]...) -> [CSSEntry] { entries.flatMap { $0 } }
    public static func buildArray(_ entries: [[CSSEntry]]) -> [CSSEntry] { entries.flatMap { $0 } }
    public static func buildOptional(_ entries: [CSSEntry]?) -> [CSSEntry] { entries ?? [] }
    public static func buildEither(first: [CSSEntry]) -> [CSSEntry] { first }
    public static func buildEither(second: [CSSEntry]) -> [CSSEntry] { second }
    public static func buildExpression(_ entry: CSSEntry) -> [CSSEntry] { [entry] }
}

@resultBuilder
public struct CSSKeyframeBuilder {
    public static func buildBlock(_ stops: [KeyframeStop]...) -> [KeyframeStop] { stops.flatMap { $0 } }
    public static func buildArray(_ stops: [[KeyframeStop]]) -> [KeyframeStop] { stops.flatMap { $0 } }
    public static func buildOptional(_ stops: [KeyframeStop]?) -> [KeyframeStop] { stops ?? [] }
    public static func buildEither(first: [KeyframeStop]) -> [KeyframeStop] { first }
    public static func buildEither(second: [KeyframeStop]) -> [KeyframeStop] { second }
    public static func buildExpression(_ stop: KeyframeStop) -> [KeyframeStop] { [stop] }
}

// Free functions

public func css(@CSSSheetBuilder _ content: () -> [CSSEntry]) -> CSSSheet {
    CSSSheet(entries: content())
}

// Declarations are variadic arguments (not a trailing closure): leading-dot
// members in argument position have no statement-continuation parse trap —
// inside a closure, a line starting with `.foo(...)` parses as a postfix
// continuation of the previous expression unless every line ends in `;`.
public func rule(_ selector: String, _ declarations: CSSDeclaration...) -> CSSEntry {
    .rule(selector: selector, declarations: declarations)
}

public func keyframes(_ name: String, @CSSKeyframeBuilder _ content: () -> [KeyframeStop]) -> CSSEntry {
    .keyframes(name: name, stops: content())
}

public func host(_ declarations: CSSDeclaration...) -> CSSEntry {
    .host(declarations: declarations)
}

public func raw(_ css: String) -> CSSEntry { .raw(css) }

/// A `@container` query whose nested rules are scoped like any other entry.
/// Pass the query text after the keyword, e.g. `container("(max-width: 380px)")`
/// or `container("sidebar (min-width: 20rem)")`.
public func container(_ query: String, @CSSSheetBuilder _ content: () -> [CSSEntry]) -> CSSEntry {
    .group(prefix: "@container \(query)", entries: content())
}

/// A `@media` query whose nested rules are scoped like any other entry.
/// Pass the query text after the keyword, e.g. `media("(max-width: 600px)")`
/// or `media("screen and (prefers-reduced-motion: reduce)")`.
public func media(_ query: String, @CSSSheetBuilder _ content: () -> [CSSEntry]) -> CSSEntry {
    .group(prefix: "@media \(query)", entries: content())
}

/// A `@starting-style` block whose nested rules are scoped like any other
/// entry. Supplies the pre-open values an element transitions *from* when it
/// first renders (e.g. a `<dialog>[open]` fading in), so CSS can animate
/// entry without JavaScript.
public func startingStyle(@CSSSheetBuilder _ content: () -> [CSSEntry]) -> CSSEntry {
    .group(prefix: "@starting-style", entries: content())
}

public func from(_ declarations: CSSDeclaration...) -> KeyframeStop {
    KeyframeStop(position: "from", declarations: declarations)
}

public func to(_ declarations: CSSDeclaration...) -> KeyframeStop {
    KeyframeStop(position: "to", declarations: declarations)
}

public func at(_ percent: Int, _ declarations: CSSDeclaration...) -> KeyframeStop {
    KeyframeStop(position: "\(percent)%", declarations: declarations)
}
