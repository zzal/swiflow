// Sources/SwiflowUI/Toggle.swift
import Swiflow

/// A labelled checkbox. Stateless free function: a native `<input type="checkbox">`
/// with the label BESIDE it — the `<label>` wraps both (implicit association, no
/// id), styled via the shared `.sw-toggle` chrome. The native checkbox gives
/// Space-to-toggle + role for free (native-leaning a11y); `accent-color` reads
/// `--sw-accent` so the check honors the theme + media layers. An optional `error:`
/// shows a `role="alert"` message and sets `aria-invalid` (e.g. a required
/// "accept terms" box). Caller `Attribute...`/`.class` land on the `<input>`.
///
///     Toggle("Subscribe to updates", isOn: $subscribed)
///     Toggle("I accept the terms", field: termsField, required: true)
@MainActor
public func Toggle(
    _ label: String,
    isOn: Binding<Bool>,
    error: String? = nil,
    required: Bool = false,
    disabled: Bool = false,
    _ attributes: Attribute...,
    onBlur: (@MainActor () -> Void)? = nil
) -> VNode {
    toggleControl(label: label, binding: isOn, error: error, required: required,
                  disabled: disabled, attributes: attributes, onBlur: onBlur)
}

/// `Field`-integrated convenience (mirrors `TextField(field:)`): pulls the bound
/// value, error display + `aria-invalid`, and blur→`markTouched` from a `Field`.
@MainActor
public func Toggle(
    _ label: String,
    field: Field<Bool>,
    required: Bool = false,
    disabled: Bool = false,
    _ attributes: Attribute...
) -> VNode {
    toggleControl(label: label, binding: field.binding, error: field.error, required: required,
                  disabled: disabled, attributes: attributes, onBlur: { field.markTouched() })
}

/// Toggle's row layout (checkbox then label text). The chrome — input attribute
/// assembly + error node — is shared with the other form controls; only the
/// layout differs (see `FieldChrome.swift`).
@MainActor
private func toggleControl(
    label labelText: String,
    binding: Binding<Bool>,
    error: String?,
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

    var rootChildren: [VNode] = [
        element("label", attributes: [.class("sw-toggle__row")], children: [
            element("input", attributes: inputAttrs),
            element("span", attributes: [.class("sw-toggle__label-text")], children: [text(labelText)]),
        ]),
    ]
    if let errorNode = fieldErrorNode(error) { rootChildren.append(errorNode) }
    return element("div", attributes: [.class("sw-toggle")], children: rootChildren)
}
