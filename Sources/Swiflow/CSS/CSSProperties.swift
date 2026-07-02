// Declarations for the css { rule(".x") { ... } } builder, as static members
// consumed via implicit-member (leading-dot) syntax:
//     rule(".card") { .padding("1rem"); .color("var(--sw-text)") }
// Static members (not free functions) so 72 single-word names don't pollute
// the module's top-level namespace and collide with app code.
extension CSSDeclaration {
    public static func backgroundColor(_ value: String) -> CSSDeclaration { .init("background-color", value) }
    public static func color(_ value: String) -> CSSDeclaration { .init("color", value) }
    public static func border(_ value: String) -> CSSDeclaration { .init("border", value) }
    public static func borderRadius(_ value: String) -> CSSDeclaration { .init("border-radius", value) }
    public static func borderTop(_ value: String) -> CSSDeclaration { .init("border-top", value) }
    public static func borderBottom(_ value: String) -> CSSDeclaration { .init("border-bottom", value) }
    public static func borderLeft(_ value: String) -> CSSDeclaration { .init("border-left", value) }
    public static func borderRight(_ value: String) -> CSSDeclaration { .init("border-right", value) }
    public static func padding(_ value: String) -> CSSDeclaration { .init("padding", value) }
    public static func paddingTop(_ value: String) -> CSSDeclaration { .init("padding-top", value) }
    public static func paddingBottom(_ value: String) -> CSSDeclaration { .init("padding-bottom", value) }
    public static func paddingLeft(_ value: String) -> CSSDeclaration { .init("padding-left", value) }
    public static func paddingRight(_ value: String) -> CSSDeclaration { .init("padding-right", value) }
    public static func margin(_ value: String) -> CSSDeclaration { .init("margin", value) }
    public static func marginTop(_ value: String) -> CSSDeclaration { .init("margin-top", value) }
    public static func marginBottom(_ value: String) -> CSSDeclaration { .init("margin-bottom", value) }
    public static func marginLeft(_ value: String) -> CSSDeclaration { .init("margin-left", value) }
    public static func marginRight(_ value: String) -> CSSDeclaration { .init("margin-right", value) }
    public static func fontSize(_ value: String) -> CSSDeclaration { .init("font-size", value) }
    public static func fontWeight(_ value: String) -> CSSDeclaration { .init("font-weight", value) }
    public static func fontFamily(_ value: String) -> CSSDeclaration { .init("font-family", value) }
    public static func lineHeight(_ value: String) -> CSSDeclaration { .init("line-height", value) }
    public static func letterSpacing(_ value: String) -> CSSDeclaration { .init("letter-spacing", value) }
    public static func textAlign(_ value: String) -> CSSDeclaration { .init("text-align", value) }
    public static func textDecoration(_ value: String) -> CSSDeclaration { .init("text-decoration", value) }
    public static func display(_ value: String) -> CSSDeclaration { .init("display", value) }
    public static func flexDirection(_ value: String) -> CSSDeclaration { .init("flex-direction", value) }
    public static func alignItems(_ value: String) -> CSSDeclaration { .init("align-items", value) }
    public static func justifyContent(_ value: String) -> CSSDeclaration { .init("justify-content", value) }
    public static func gap(_ value: String) -> CSSDeclaration { .init("gap", value) }
    public static func width(_ value: String) -> CSSDeclaration { .init("width", value) }
    public static func height(_ value: String) -> CSSDeclaration { .init("height", value) }
    public static func maxWidth(_ value: String) -> CSSDeclaration { .init("max-width", value) }
    public static func minHeight(_ value: String) -> CSSDeclaration { .init("min-height", value) }
    public static func overflow(_ value: String) -> CSSDeclaration { .init("overflow", value) }
    public static func opacity(_ value: String) -> CSSDeclaration { .init("opacity", value) }
    public static func transform(_ value: String) -> CSSDeclaration { .init("transform", value) }
    public static func transition(_ value: String) -> CSSDeclaration { .init("transition", value) }
    public static func animation(_ value: String) -> CSSDeclaration { .init("animation", value) }
    public static func boxShadow(_ value: String) -> CSSDeclaration { .init("box-shadow", value) }
    public static func cursor(_ value: String) -> CSSDeclaration { .init("cursor", value) }
    public static func position(_ value: String) -> CSSDeclaration { .init("position", value) }
    public static func top(_ value: String) -> CSSDeclaration { .init("top", value) }
    public static func left(_ value: String) -> CSSDeclaration { .init("left", value) }
    public static func right(_ value: String) -> CSSDeclaration { .init("right", value) }
    public static func bottom(_ value: String) -> CSSDeclaration { .init("bottom", value) }
    public static func zIndex(_ value: String) -> CSSDeclaration { .init("z-index", value) }
    public static func outline(_ value: String) -> CSSDeclaration { .init("outline", value) }
    public static func outlineOffset(_ value: String) -> CSSDeclaration { .init("outline-offset", value) }

    // MARK: - Modern HTML/CSS surfaces (added with HelloWorld elevation)
    public static func positionAnchor(_ value: String) -> CSSDeclaration { .init("position-anchor", value) }
    public static func positionArea(_ value: String) -> CSSDeclaration { .init("position-area", value) }
    public static func anchorName(_ value: String) -> CSSDeclaration { .init("anchor-name", value) }
    public static func viewTransitionName(_ value: String) -> CSSDeclaration { .init("view-transition-name", value) }
    public static func interpolateSize(_ value: String) -> CSSDeclaration { .init("interpolate-size", value) }
    public static func accentColor(_ value: String) -> CSSDeclaration { .init("accent-color", value) }
    public static func colorScheme(_ value: String) -> CSSDeclaration { .init("color-scheme", value) }
    public static func inset(_ value: String) -> CSSDeclaration { .init("inset", value) }
    public static func insetBlockEnd(_ value: String) -> CSSDeclaration { .init("inset-block-end", value) }
    public static func insetInline(_ value: String) -> CSSDeclaration { .init("inset-inline", value) }
    public static func placeItems(_ value: String) -> CSSDeclaration { .init("place-items", value) }
    public static func placeContent(_ value: String) -> CSSDeclaration { .init("place-content", value) }
    public static func marginInline(_ value: String) -> CSSDeclaration { .init("margin-inline", value) }
    public static func backdropFilter(_ value: String) -> CSSDeclaration { .init("backdrop-filter", value) }
    public static func transitionBehavior(_ value: String) -> CSSDeclaration { .init("transition-behavior", value) }
    public static func containerType(_ value: String) -> CSSDeclaration { .init("container-type", value) }
    public static func background(_ value: String) -> CSSDeclaration { .init("background", value) }
    public static func pointerEvents(_ value: String) -> CSSDeclaration { .init("pointer-events", value) }
    public static func flexWrap(_ value: String) -> CSSDeclaration { .init("flex-wrap", value) }
    public static func flex(_ value: String) -> CSSDeclaration { .init("flex", value) }
    public static func listStyle(_ value: String) -> CSSDeclaration { .init("list-style", value) }

    // Escape hatch — any property name/value pair. "property" mirrors MDN's "CSS
    // property"; it sits in a different syntactic position than the element-layer
    // `Attribute.property`/`.prop` (a DOM/IDL property), so there is no collision.
    public static func property(_ name: String, _ value: String) -> CSSDeclaration { .init(name, value) }

    /// Define a CSS custom property (`.cssVar("--accent", "…")`). An intent-revealing
    /// alias over `property` for the `--x` case — and the same verb as the
    /// element-layer `Attribute.cssVar`, so "cssVar" means the identical thing
    /// whether you're writing a sheet or an inline style.
    public static func cssVar(_ name: String, _ value: String) -> CSSDeclaration { property(name, value) }
}
