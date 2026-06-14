// Sources/SwiflowUI/TextField.swift
import Swiflow

/// The `type` of a single-line `TextField`, mapped to the native `<input>`
/// `type` attribute (mobile keyboards, native validation/affordances). The value
/// is always a `String`; bind a numeric `type: .number` to a `Binding<String>`.
public enum TextFieldType: Equatable {
    case text, email, password, number, search, tel, url
    var attributeValue: String {
        switch self {
        case .text:     return "text"
        case .email:    return "email"
        case .password: return "password"
        case .number:   return "number"
        case .search:   return "search"
        case .tel:      return "tel"
        case .url:      return "url"
        }
    }
}

/// A labelled, token-styled single-line text field. Stateless free function
/// (like `Button`): a thin wrapper over a native `<input>` plus label + error
/// chrome, styled via the shared global `.sw-field` sheet. The `<label>` WRAPS
/// the `<input>` (implicit association — no id juggling); the error message
/// carries `role="alert"` and the input gets `aria-invalid`, so validation state
/// is announced. Every value reads a `--sw-*` token, so the M2 media-feature
/// layers apply automatically. Caller `Attribute...` (and a caller `.class`)
/// land on the `<input>` and apply last, so they win / extend (autocomplete,
/// name, maxlength, …) — but don't pass `.value`/`.on(.input)` (they'd overwrite
/// the binding; drive the value through `text:`).
///
///     TextField("Name", text: $name)
///     TextField("Email", text: $email, type: .email, error: emailError)
@MainActor
public func TextField(
    _ label: String,
    text: Binding<String>,
    type: TextFieldType = .text,
    placeholder: String = "",
    error: String? = nil,
    size: ControlSize = .md,
    required: Bool = false,
    disabled: Bool = false,
    _ attributes: Attribute...,
    onBlur: (@MainActor () -> Void)? = nil
) -> VNode {
    fieldControl(label: label, binding: text, type: type, placeholder: placeholder,
                 error: error, size: size, required: required, disabled: disabled,
                 attributes: attributes, onBlur: onBlur)
}

/// `Field`-integrated convenience: pulls the binding, error, and blur→`markTouched`
/// wiring out of a `Field`, collapsing the hand-rolled per-field form boilerplate
/// (wrapper + label + `.on(.blur)` + error display) to one call.
///
///     let email = Field("email", $email, $ctrl, .required(), .email)
///     TextField("Email", field: email, type: .email)
@MainActor
public func TextField(
    _ label: String,
    field: Field<String>,
    type: TextFieldType = .text,
    placeholder: String = "",
    size: ControlSize = .md,
    required: Bool = false,
    disabled: Bool = false,
    _ attributes: Attribute...
) -> VNode {
    fieldControl(label: label, binding: field.binding, type: type, placeholder: placeholder,
                 error: field.error, size: size, required: required, disabled: disabled,
                 attributes: attributes, onBlur: { field.markTouched() })
}

/// Shared field-chrome lowering for the text controls. (`binding`, not `text`, to
/// avoid shadowing the `text(_:)` node factory.)
@MainActor
private func fieldControl(
    label labelText: String,
    binding: Binding<String>,
    type: TextFieldType,
    placeholder: String,
    error: String?,
    size: ControlSize,
    required: Bool,
    disabled: Bool,
    attributes: [Attribute],
    onBlur: (@MainActor () -> Void)?
) -> VNode {
    ensureBaseStyles()
    installFieldStyles()

    var base: [Attribute] = [.attr("type", type.attributeValue), .value(binding)]
    if !placeholder.isEmpty { base.append(.attr("placeholder", placeholder)) }
    let inputAttrs = controlInputAttributes(base, error: error, required: required,
                                            disabled: disabled, onBlur: onBlur, caller: attributes)

    var rootChildren: [VNode] = [
        element("label", attributes: [.class("sw-field__label")], children: [
            element("span", attributes: [.class("sw-field__label-text")], children: [text(labelText)]),
            element("input", attributes: inputAttrs),
        ]),
    ]
    if let errorNode = fieldErrorNode(error) { rootChildren.append(errorNode) }
    return element("div", attributes: [.class("sw-field sw-field--\(size.modifierClass)")],
                   children: rootChildren)
}
