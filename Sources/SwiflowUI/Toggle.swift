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
    _ attributes: Attribute...,
    onBlur: (@MainActor () -> Void)? = nil
) -> VNode {
    switchControl(label: label, binding: isOn, error: error, size: size, required: required,
                  disabled: disabled, attributes: attributes, onBlur: onBlur)
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
    _ attributes: Attribute...
) -> VNode {
    switchControl(label: label, binding: field.binding, error: field.error, size: size, required: required,
                  disabled: disabled, attributes: attributes, onBlur: { field.markTouched() })
}

@MainActor
private func switchControl(
    label labelText: String,
    binding: Binding<Bool>,
    error: String?,
    size: ControlSize,
    required: Bool,
    disabled: Bool,
    attributes: [Attribute],
    onBlur: (@MainActor () -> Void)?
) -> VNode {
    ensureBaseStyles()
    installFieldStyles()

    let inputAttrs = controlInputAttributes(
        [.attr("type", "checkbox"), .attr("role", "switch"), .checked(binding)],
        error: error, required: required, disabled: disabled, onBlur: onBlur, caller: attributes
    )

    let rowClass = disabled ? "sw-switch__row sw-switch__row--disabled" : "sw-switch__row"
    var rootChildren: [VNode] = [
        element("label", attributes: [.class(rowClass)], children: [
            element("input", attributes: inputAttrs),
            element("span", attributes: [.class("sw-switch__track")], children: [
                element("span", attributes: [.class("sw-switch__thumb")]),
            ]),
            element("span", attributes: [.class("sw-switch__label-text")], children: [text(labelText)]),
        ]),
    ]
    if let errorNode = fieldErrorNode(error) { rootChildren.append(errorNode) }
    return element("div", attributes: [.class("sw-switch sw-switch--\(size.modifierClass)")], children: rootChildren)
}
