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
public struct CSSRuleBuilder {
    public static func buildBlock(_ decls: [CSSDeclaration]...) -> [CSSDeclaration] { decls.flatMap { $0 } }
    public static func buildArray(_ decls: [[CSSDeclaration]]) -> [CSSDeclaration] { decls.flatMap { $0 } }
    public static func buildOptional(_ decls: [CSSDeclaration]?) -> [CSSDeclaration] { decls ?? [] }
    public static func buildEither(first: [CSSDeclaration]) -> [CSSDeclaration] { first }
    public static func buildEither(second: [CSSDeclaration]) -> [CSSDeclaration] { second }
    public static func buildExpression(_ decl: CSSDeclaration) -> [CSSDeclaration] { [decl] }
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

public func rule(_ selector: String, @CSSRuleBuilder _ content: () -> [CSSDeclaration]) -> CSSEntry {
    .rule(selector: selector, declarations: content())
}

public func keyframes(_ name: String, @CSSKeyframeBuilder _ content: () -> [KeyframeStop]) -> CSSEntry {
    .keyframes(name: name, stops: content())
}

public func from(@CSSRuleBuilder _ content: () -> [CSSDeclaration]) -> KeyframeStop {
    KeyframeStop(position: "from", declarations: content())
}

public func to(@CSSRuleBuilder _ content: () -> [CSSDeclaration]) -> KeyframeStop {
    KeyframeStop(position: "to", declarations: content())
}

public func at(_ percent: Int, @CSSRuleBuilder _ content: () -> [CSSDeclaration]) -> KeyframeStop {
    KeyframeStop(position: "\(percent)%", declarations: content())
}
