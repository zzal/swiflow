import Swiflow

/// How the horizontal layout sizes its label column.
public enum FieldLabelColumn: Equatable {
    /// Fixed shared width (`--sw-field-label-width`, default 10rem) so
    /// stacked fields align — the settings-form look. The default.
    case fixed
    /// The column hugs this field's own label (`max-content`). Right for
    /// standalone fields or dense inline forms; stacked hug fields do NOT
    /// share a column (each field is its own grid).
    case hug
}

/// How a field lays its label against its control.
public enum FieldLayout: Equatable {
    /// Label above the control — the default, today's look.
    case vertical
    /// Label beside the control: a `.fixed` shared-width column
    /// (`--sw-field-label-width`) so stacked fields align, or a `.hug`
    /// column sized to this field's own label.
    case horizontal(labelColumn: FieldLabelColumn)

    /// Source-compat sugar: the fixed-column horizontal layout, spelled
    /// `.horizontal` as before the `labelColumn:` dimension existed.
    public static var horizontal: FieldLayout { .horizontal(labelColumn: .fixed) }

    var rootModifierClasses: [String] {
        switch self {
        case .vertical:                        return []
        case .horizontal(labelColumn: .fixed): return ["sw-field--h"]
        case .horizontal(labelColumn: .hug):   return ["sw-field--h", "sw-field--h-hug"]
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

/// The field-chrome root's class list: a base class family (`sw-field` by
/// default; `sw-switch`/`sw-check`/`sw-radio` for the row/group controls,
/// which have their own size-modifier CSS unrelated to `.sw-field`'s input
/// padding) + size modifier + layout modifiers + any control-specific extras
/// (a caller's classes, or a control's own identity class like Autocomplete's
/// `sw-ac`). Every field-chrome root goes through this so a new `FieldLayout`
/// case can't land in one root and not another.
@MainActor
func fieldRootClasses(base: String = "sw-field", size: ControlSize, layout: FieldLayout, extra: [String] = []) -> [String] {
    var classes = [base, "\(base)--\(size.modifierClass)"] + extra
    classes += layout.rootModifierClasses
    return classes
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
    let classes = fieldRootClasses(size: size, layout: layout, extra: extraClasses)

    // Horizontal is a two-column grid (label line | control): 2+ control nodes
    // (possible only via the public LabeledField builder) must occupy ONE grid
    // item or the extras wrap into the label column. Vertical stacks anyway,
    // and single-node fields (every built-in control) keep their exact DOM.
    let controlSlot: [VNode] = (layout != .vertical && controls.count > 1)
        ? [element("span", attributes: [.class("sw-field__controls")], children: controls)]
        : controls
    var rootChildren: [VNode] = [
        element("label", attributes: [.class("sw-field__label")],
                children: [fieldLabelLine(label, prefix: prefix, suffix: suffix)] + controlSlot),
    ]
    if let errorNode = fieldErrorNode(error) { rootChildren.append(errorNode) }
    return element("div", attributes: [.class(classes.joined(separator: " "))] + rootAttrs,
                   children: rootChildren)
}

/// The single-input control lowering every built-in field (TextField, NumberField,
/// TextArea, Select, Slider) delegates to: styles-once, `controlInputAttributes` for
/// the input-level aria/disabled/blur/caller assembly, `makeControl` to turn the
/// assembled attributes into the control's own element (the one genuinely
/// control-specific step — an `<input>`, a `<textarea>`, a `<select>` with option
/// children, a slider's `<input>` plus its fill style), then `labeledFieldChrome`
/// for the label/error/layout wrapper. Not `private`: Swift's top-level `private` is
/// file-scoped, and this is shared across files. (Autocomplete doesn't use this — its
/// DOM has a for-associated label plus sibling controls, not one wrapped input.)
@MainActor
func fieldChromeLowering(
    label: String,
    layout: FieldLayout,
    error: String?,
    size: ControlSize,
    required: Bool,
    disabled: Bool,
    labelPrefix: VNode?,
    labelSuffix: VNode?,
    base: [Attribute],
    caller: [Attribute],
    onBlur: (@MainActor () -> Void)?,
    makeControl: (_ attrs: [Attribute]) -> VNode
) -> VNode {
    ensureBaseStyles()
    installFieldStyles()
    let inputAttrs = controlInputAttributes(base, error: error, required: required,
                                            disabled: disabled, onBlur: onBlur, caller: caller)
    return labeledFieldChrome(label: label, layout: layout, prefix: labelPrefix, suffix: labelSuffix,
                              error: error, size: size, controls: [makeControl(inputAttrs)])
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
/// Horizontal's label column is a fixed shared width by default
/// (`--sw-field-label-width`, so stacked fields align); pass
/// `layout: .horizontal(labelColumn: .hug)` for a column that hugs this
/// field's own label instead.
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
