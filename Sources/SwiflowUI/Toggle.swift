// Sources/SwiflowUI/Toggle.swift
import Swiflow

/// A switch — for a binary **setting that takes effect immediately** (dark mode,
/// notifications on/off). For *selection / confirmation* that's submitted with a
/// form ("I accept the terms", multi-select), use ``Checkbox`` instead.
///
/// Stateless free function. Built on a native `<input type="checkbox">` with
/// `role="switch"` (so it keeps Space-to-toggle, focus, and state natively but is
/// announced as a switch), visually presented as a sliding track + thumb. The
/// real input is visually hidden; the wrapping `<label>` makes the whole control
/// clickable. Every value reads a `--sw-*` token (track `--sw-border`→`--sw-accent`,
/// thumb `--sw-surface`, slide via `--sw-duration` so reduced-motion stops it), so
/// the M2 media layers apply. Caller `Attribute...`/`.class` land on the `<input>` —
/// don't pass `.checked`/`.on(.change)` (they'd overwrite the binding; use `isOn:`).
///
///     Toggle("Dark mode", isOn: $isDark)
///     Toggle("Email notifications", field: notifyField)
@MainActor
public func Toggle(
    _ label: String,
    isOn: Binding<Bool>,
    error: String? = nil,
    size: ControlSize = .md,
    required: Bool = false,
    disabled: Bool = false,
    layout: FieldLayout = .vertical,
    _ attributes: Attribute...,
    onBlur: (@MainActor () -> Void)? = nil
) -> VNode {
    switchControl(label: label, binding: isOn, error: error, size: size, required: required,
                  disabled: disabled, layout: layout, attributes: attributes, onBlur: onBlur)
}

/// `Field`-integrated convenience (mirrors `TextField(field:)`): wires the bound
/// value, error + `aria-invalid`, and blur→`markTouched`.
@MainActor
public func Toggle(
    _ label: String,
    field: Field<Bool>,
    size: ControlSize = .md,
    required: Bool = false,
    disabled: Bool = false,
    layout: FieldLayout = .vertical,
    _ attributes: Attribute...
) -> VNode {
    switchControl(label: label, binding: field.binding, error: field.error, size: size, required: required,
                  disabled: disabled, layout: layout, attributes: attributes, onBlur: { field.markTouched() })
}

/// Horizontal layout (see `LabeledField`'s `FieldLayout`) splits the label text
/// into a `for`-associated column-1 element and leaves only the switch itself
/// (input + track/thumb) as the row's content — clicking the split-out text
/// still toggles the control natively via `for=` click-forwarding. Vertical
/// (the default) keeps today's DOM byte-for-byte: label text inline inside the
/// same wrapping row, no `id`/`for` added.
@MainActor
private func switchControl(
    label labelText: String,
    binding: Binding<Bool>,
    error: String?,
    size: ControlSize,
    required: Bool,
    disabled: Bool,
    layout: FieldLayout,
    attributes: [Attribute],
    onBlur: (@MainActor () -> Void)?
) -> VNode {
    ensureBaseStyles()
    installFieldStyles()

    let horizontal = layout != .vertical
    let controlID = horizontal ? "sw-switch-" + fieldSlug(labelText, fallback: "toggle") : nil

    var inputBase: [Attribute] = [.attr("type", "checkbox"), .attr("role", "switch"), .checked(binding)]
    if let controlID { inputBase.append(.attr("id", controlID)) }
    let inputAttrs = controlInputAttributes(
        inputBase, error: error, required: required, disabled: disabled, onBlur: onBlur, caller: attributes
    )

    let rowClass = disabled ? "sw-switch__row sw-switch__row--disabled" : "sw-switch__row"
    var rowChildren: [VNode] = [
        element("input", attributes: inputAttrs),
        element("span", attributes: [.class("sw-switch__track")], children: [
            element("span", attributes: [.class("sw-switch__thumb")]),
        ]),
    ]

    var rootChildren: [VNode] = []
    if let controlID {
        rootChildren.append(
            element("label", attributes: [.class("sw-field__label sw-field__label--standalone"), .attr("for", controlID)],
                    children: [fieldLabelLine(labelText, prefix: nil, suffix: nil)])
        )
    } else {
        rowChildren.append(element("span", attributes: [.class("sw-switch__label-text")], children: [text(labelText)]))
    }
    rootChildren.append(element("label", attributes: [.class(rowClass)], children: rowChildren))
    if let errorNode = fieldErrorNode(error) { rootChildren.append(errorNode) }

    let rootClasses = fieldRootClasses(base: "sw-switch", size: size, layout: layout)
    return element("div", attributes: [.class(rootClasses.joined(separator: " "))], children: rootChildren)
}
