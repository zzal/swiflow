// Sources/SwiflowUI/Checkbox.swift
import Swiflow

/// A checkbox — for **selection / confirmation** that's reviewed and submitted
/// ("I accept the terms", picking items, an opt-in that takes effect on submit).
/// For a binary *setting that applies immediately* (dark mode), use ``Toggle``
/// (a switch) instead.
///
/// Stateless free function: a native `<input type="checkbox">` with the label
/// BESIDE it (the `<label>` wraps both — implicit association, no id), styled via
/// the shared `.sw-check` chrome. Native checkbox gives Space-to-toggle + role for
/// free; `accent-color` reads `--sw-accent` so the check honors theme + media
/// layers. An optional `error:` shows a `role="alert"` message and sets
/// `aria-invalid` (the classic required "accept terms" box). Caller
/// `Attribute...`/`.class` land on the `<input>` — don't pass `.checked`/
/// `.on(.change)` (they'd overwrite the binding; use `isOn:`).
///
///     Checkbox("Select all", isOn: $all)
///     Checkbox("I accept the terms", field: termsField, required: true)
@MainActor
public func Checkbox(
    _ label: String,
    isOn: Binding<Bool>,
    error: String? = nil,
    size: ControlSize = .md,
    required: Bool = false,
    disabled: Bool = false,
    _ attributes: Attribute...,
    onBlur: (@MainActor () -> Void)? = nil
) -> VNode {
    checkboxControl(label: label, binding: isOn, error: error, size: size, required: required,
                    disabled: disabled, attributes: attributes, onBlur: onBlur)
}

/// `Field`-integrated convenience (mirrors `TextField(field:)`): wires the bound
/// value, error + `aria-invalid`, and blur→`markTouched`.
@MainActor
public func Checkbox(
    _ label: String,
    field: Field<Bool>,
    size: ControlSize = .md,
    required: Bool = false,
    disabled: Bool = false,
    _ attributes: Attribute...
) -> VNode {
    checkboxControl(label: label, binding: field.binding, error: field.error, size: size, required: required,
                    disabled: disabled, attributes: attributes, onBlur: { field.markTouched() })
}

@MainActor
private func checkboxControl(
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
        [.attr("type", "checkbox"), .checked(binding)],
        error: error, required: required, disabled: disabled, onBlur: onBlur, caller: attributes
    )

    let rowClass = disabled ? "sw-check__row sw-check__row--disabled" : "sw-check__row"
    var rootChildren: [VNode] = [
        element("label", attributes: [.class(rowClass)], children: [
            element("input", attributes: inputAttrs),
            element("span", attributes: [.class("sw-check__label-text")], children: [text(labelText)]),
        ]),
    ]
    if let errorNode = fieldErrorNode(error) { rootChildren.append(errorNode) }
    return element("div", attributes: [.class("sw-check sw-check--\(size.modifierClass)")], children: rootChildren)
}
