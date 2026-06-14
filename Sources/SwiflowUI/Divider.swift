// Sources/SwiflowUI/Divider.swift
import Swiflow

/// Orientation of a `Divider`. A `.horizontal` rule separates stacked rows
/// (use in a `VStack`); a `.vertical` rule separates side-by-side items (use in
/// an `HStack`). The parent stack's direction can't be inferred from the rule
/// itself, so the orientation is explicit. The cases mirror the values a
/// separator's `aria-orientation` can take.
public enum Orientation: Equatable { case horizontal, vertical }

/// A thin separating line drawn with the `--sw-border` color at
/// `--sw-border-width` thickness. Lowers to a semantic `<hr>` (implicit
/// `role=separator`); the vertical form adds `aria-orientation="vertical"`
/// since the native default is horizontal.
///
/// The line is painted with `background-color` + an explicit `height`/`width`
/// rather than a `border` longhand: `ElementData.style` is an unordered
/// dictionary, so combining the `border` shorthand (to reset the `<hr>` default)
/// with a `border-top`/`border-left` longhand would be serialization-order
/// dependent. These properties don't overlap, so the result is deterministic.
@MainActor
public func Divider(_ orientation: Orientation = .horizontal, _ attributes: Attribute...) -> VNode {
    ensureBaseStyles()
    var styles: [Attribute] = [
        .style("border", "none"),                       // reset the <hr> default 3-D rule
        .style("margin", "0"),
        .style("background-color", "var(--sw-border)"),
        .style("align-self", "stretch"),                // match sibling extent in a flex stack
    ]
    switch orientation {
    case .horizontal:
        // A block <hr> already fills the inline axis; height paints the thickness.
        styles.append(.style("height", "var(--sw-border-width)"))
    case .vertical:
        styles.append(.style("width", "var(--sw-border-width)"))
        // `align-self: stretch` only confers height inside a stretch-aligned
        // flex row. min-height keeps a vertical rule visible everywhere else —
        // a centered HStack, a grid cell, plain block flow — instead of
        // collapsing to 0 height.
        styles.append(.style("min-height", "1em"))
        styles.append(.attr("aria-orientation", "vertical"))
    }
    return element("hr", attributes: styles + attributes)
}
