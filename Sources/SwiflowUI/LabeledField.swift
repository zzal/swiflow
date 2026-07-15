import Swiflow

/// How a field lays its label against its control.
public enum FieldLayout: Equatable {
    /// Label above the control — the default, today's look.
    case vertical
    /// Label beside the control in a fixed-width column
    /// (`--sw-field-label-width`), so stacked fields align like a settings form.
    case horizontal

    var rootModifierClass: String? {
        switch self {
        case .vertical:   return nil
        case .horizontal: return "sw-field--h"
        }
    }
}

/// The label LINE: optional prefix adornment, the label text, optional suffix
/// adornment, rowed up in one span. Shared by every field control — including
/// Autocomplete, whose label doesn't wrap its control and therefore can't use
/// the full chrome below.
///
/// Adornments are `VNode`s: `text("optional")` renders subtle automatically
/// (the wrapping span is muted/small), and `Icon(svg:)` inherits the muted
/// color via `currentColor`.
@MainActor
func fieldLabelLine(_ label: String, prefix: VNode?, suffix: VNode?) -> VNode {
    var children: [VNode] = []
    if let prefix {
        children.append(element("span", attributes: [.class("sw-field__label-prefix")], children: [prefix]))
    }
    children.append(element("span", attributes: [.class("sw-field__label-text")], children: [text(label)]))
    if let suffix {
        children.append(element("span", attributes: [.class("sw-field__label-suffix")], children: [suffix]))
    }
    return element("span", attributes: [.class("sw-field__label-line")], children: children)
}

/// The full shared chrome the wrapping controls delegate to: root `div.sw-field`
/// (size + layout modifiers), a wrapping `<label>` containing the label line and
/// the control(s), and the standard error node. This is `LabeledField` minus the
/// public conveniences — controls call this with their prepared control node(s).
@MainActor
func labeledFieldChrome(
    label: String,
    layout: FieldLayout,
    prefix: VNode?,
    suffix: VNode?,
    error: String?,
    size: ControlSize,
    extraClasses: [String] = [],
    rootAttrs: [Attribute] = [],
    controls: [VNode]
) -> VNode {
    var classes = ["sw-field", "sw-field--\(size.modifierClass)"]
    if let modifier = layout.rootModifierClass { classes.append(modifier) }
    classes += extraClasses

    var rootChildren: [VNode] = [
        element("label", attributes: [.class("sw-field__label")],
                children: [fieldLabelLine(label, prefix: prefix, suffix: suffix)] + controls),
    ]
    if let errorNode = fieldErrorNode(error) { rootChildren.append(errorNode) }
    return element("div", attributes: [.class(classes.joined(separator: " "))] + rootAttrs,
                   children: rootChildren)
}

/// The shared field chrome as a public component — for CUSTOM controls that want
/// the kit's label/error/size/layout treatment. The built-in controls
/// (TextField/Select/…) already render this internally; don't wrap them in it
/// (you'd nest two labels).
///
///     LabeledField("API key", layout: .horizontal, suffix: text("optional")) {
///         element("input", attributes: [.attr("type", "password")])
///     }
///
/// Caller `Attribute...`/`.class` merge onto the ROOT div.
@MainActor
public func LabeledField(
    _ label: String,
    layout: FieldLayout = .vertical,
    prefix: VNode? = nil,
    suffix: VNode? = nil,
    error: String? = nil,
    size: ControlSize = .md,
    _ attributes: Attribute...,
    @ChildrenBuilder control: () -> [VNode]
) -> VNode {
    ensureBaseStyles()
    installFieldStyles()
    let (callerClasses, callerRest) = splitClasses(attributes)
    return labeledFieldChrome(label: label, layout: layout, prefix: prefix, suffix: suffix,
                              error: error, size: size,
                              extraClasses: callerClasses, rootAttrs: callerRest,
                              controls: control())
}
