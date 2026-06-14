// Sources/SwiflowUI/Divider.swift
import Swiflow

/// Layout axis for a `Divider`. A `.horizontal` rule separates stacked rows
/// (use in a `VStack`); a `.vertical` rule separates side-by-side items (use in
/// an `HStack`). The parent stack's direction can't be inferred from the rule
/// itself, so the axis is explicit.
public enum Axis: Equatable { case horizontal, vertical }

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
public func Divider(_ axis: Axis = .horizontal, _ attributes: Attribute...) -> VNode {
    ensureBaseStyles()
    var styles: [Attribute] = [
        .style("border", "none"),                       // reset the <hr> default 3-D rule
        .style("margin", "0"),
        .style("background-color", "var(--sw-border)"),
        .style("align-self", "stretch"),                // fill the cross axis in a flex stack
    ]
    switch axis {
    case .horizontal:
        styles.append(.style("height", "var(--sw-border-width)"))
    case .vertical:
        styles.append(.style("width", "var(--sw-border-width)"))
        styles.append(.attr("aria-orientation", "vertical"))
    }
    return element("hr", attributes: styles + attributes)
}
