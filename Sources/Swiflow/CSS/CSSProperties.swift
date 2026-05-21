// All functions are free functions for use inside @CSSRuleBuilder contexts.

public func backgroundColor(_ value: String) -> CSSDeclaration { .init("background-color", value) }
public func color(_ value: String) -> CSSDeclaration { .init("color", value) }
public func border(_ value: String) -> CSSDeclaration { .init("border", value) }
public func borderRadius(_ value: String) -> CSSDeclaration { .init("border-radius", value) }
public func borderTop(_ value: String) -> CSSDeclaration { .init("border-top", value) }
public func borderBottom(_ value: String) -> CSSDeclaration { .init("border-bottom", value) }
public func borderLeft(_ value: String) -> CSSDeclaration { .init("border-left", value) }
public func borderRight(_ value: String) -> CSSDeclaration { .init("border-right", value) }
public func padding(_ value: String) -> CSSDeclaration { .init("padding", value) }
public func paddingTop(_ value: String) -> CSSDeclaration { .init("padding-top", value) }
public func paddingBottom(_ value: String) -> CSSDeclaration { .init("padding-bottom", value) }
public func paddingLeft(_ value: String) -> CSSDeclaration { .init("padding-left", value) }
public func paddingRight(_ value: String) -> CSSDeclaration { .init("padding-right", value) }
public func margin(_ value: String) -> CSSDeclaration { .init("margin", value) }
public func marginTop(_ value: String) -> CSSDeclaration { .init("margin-top", value) }
public func marginBottom(_ value: String) -> CSSDeclaration { .init("margin-bottom", value) }
public func marginLeft(_ value: String) -> CSSDeclaration { .init("margin-left", value) }
public func marginRight(_ value: String) -> CSSDeclaration { .init("margin-right", value) }
public func fontSize(_ value: String) -> CSSDeclaration { .init("font-size", value) }
public func fontWeight(_ value: String) -> CSSDeclaration { .init("font-weight", value) }
public func fontFamily(_ value: String) -> CSSDeclaration { .init("font-family", value) }
public func lineHeight(_ value: String) -> CSSDeclaration { .init("line-height", value) }
public func letterSpacing(_ value: String) -> CSSDeclaration { .init("letter-spacing", value) }
public func textAlign(_ value: String) -> CSSDeclaration { .init("text-align", value) }
public func textDecoration(_ value: String) -> CSSDeclaration { .init("text-decoration", value) }
public func display(_ value: String) -> CSSDeclaration { .init("display", value) }
public func flexDirection(_ value: String) -> CSSDeclaration { .init("flex-direction", value) }
public func alignItems(_ value: String) -> CSSDeclaration { .init("align-items", value) }
public func justifyContent(_ value: String) -> CSSDeclaration { .init("justify-content", value) }
public func gap(_ value: String) -> CSSDeclaration { .init("gap", value) }
public func width(_ value: String) -> CSSDeclaration { .init("width", value) }
public func height(_ value: String) -> CSSDeclaration { .init("height", value) }
public func maxWidth(_ value: String) -> CSSDeclaration { .init("max-width", value) }
public func minHeight(_ value: String) -> CSSDeclaration { .init("min-height", value) }
public func overflow(_ value: String) -> CSSDeclaration { .init("overflow", value) }
public func opacity(_ value: String) -> CSSDeclaration { .init("opacity", value) }
public func transform(_ value: String) -> CSSDeclaration { .init("transform", value) }
public func transition(_ value: String) -> CSSDeclaration { .init("transition", value) }
public func animation(_ value: String) -> CSSDeclaration { .init("animation", value) }
public func boxShadow(_ value: String) -> CSSDeclaration { .init("box-shadow", value) }
public func cursor(_ value: String) -> CSSDeclaration { .init("cursor", value) }
public func position(_ value: String) -> CSSDeclaration { .init("position", value) }
public func top(_ value: String) -> CSSDeclaration { .init("top", value) }
public func left(_ value: String) -> CSSDeclaration { .init("left", value) }
public func right(_ value: String) -> CSSDeclaration { .init("right", value) }
public func bottom(_ value: String) -> CSSDeclaration { .init("bottom", value) }
public func zIndex(_ value: String) -> CSSDeclaration { .init("z-index", value) }

// Escape hatches
public func property(_ name: String, _ value: String) -> CSSDeclaration { .init(name, value) }
public func cssVar(_ name: String, _ value: String) -> CSSDeclaration { .init(name, value) }
