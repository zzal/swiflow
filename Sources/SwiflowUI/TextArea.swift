// Sources/SwiflowUI/TextArea.swift
import Swiflow

/// A labelled, token-styled multi-line text field. Stateless free function
/// mirroring `TextField`: native `<textarea>` + label/error chrome via the
/// shared `.sw-field` sheet (which already styles `textarea`). The `<label>`
/// wraps the control; errors carry `role="alert"` + `aria-invalid`. Caller
/// attributes land on the `<textarea>` and apply last — but don't pass
/// `.value`/`.on(.input)`; drive the value through `text:`.
///
///     TextArea("Bio", text: $bio, rows: 6, placeholder: "Tell us about you…")
@MainActor
public func TextArea(
    _ label: String,
    text: Binding<String>,
    rows: Int = 3,
    placeholder: String = "",
    error: String? = nil,
    size: ControlSize = .md,
    required: Bool = false,
    disabled: Bool = false,
    layout: FieldLayout = .vertical,
    labelPrefix: VNode? = nil,
    labelSuffix: VNode? = nil,
    _ attributes: Attribute...,
    onBlur: (@MainActor () -> Void)? = nil
) -> VNode {
    textAreaControl(label: label, binding: text, rows: rows, placeholder: placeholder,
                    error: error, size: size, required: required, disabled: disabled,
                    layout: layout, labelPrefix: labelPrefix, labelSuffix: labelSuffix,
                    attributes: attributes, onBlur: onBlur)
}

/// `Field`-integrated convenience, mirroring `TextField(_:field:)`.
@MainActor
public func TextArea(
    _ label: String,
    field: Field<String>,
    rows: Int = 3,
    placeholder: String = "",
    size: ControlSize = .md,
    required: Bool = false,
    disabled: Bool = false,
    layout: FieldLayout = .vertical,
    labelPrefix: VNode? = nil,
    labelSuffix: VNode? = nil,
    _ attributes: Attribute...
) -> VNode {
    textAreaControl(label: label, binding: field.binding, rows: rows, placeholder: placeholder,
                    error: field.error, size: size, required: required, disabled: disabled,
                    layout: layout, labelPrefix: labelPrefix, labelSuffix: labelSuffix,
                    attributes: attributes, onBlur: { field.markTouched() })
}

/// Shared field-chrome lowering, mirroring `TextField`'s `fieldControl`.
@MainActor
private func textAreaControl(
    label labelText: String,
    binding: Binding<String>,
    rows: Int,
    placeholder: String,
    error: String?,
    size: ControlSize,
    required: Bool,
    disabled: Bool,
    layout: FieldLayout,
    labelPrefix: VNode?,
    labelSuffix: VNode?,
    attributes: [Attribute],
    onBlur: (@MainActor () -> Void)?
) -> VNode {
    ensureBaseStyles()
    installFieldStyles()

    var base: [Attribute] = [.attr("rows", rows), .value(binding)]
    if !placeholder.isEmpty { base.append(.placeholder(placeholder)) }
    let controlAttrs = controlInputAttributes(base, error: error, required: required,
                                              disabled: disabled, onBlur: onBlur, caller: attributes)

    return labeledFieldChrome(label: labelText, layout: layout, prefix: labelPrefix,
                              suffix: labelSuffix, error: error, size: size,
                              controls: [element("textarea", attributes: controlAttrs)])
}
