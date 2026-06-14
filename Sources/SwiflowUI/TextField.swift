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
/// name, maxlength, …).
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
    disabled: Bool = false,
    _ attributes: Attribute...,
    onBlur: (@MainActor () -> Void)? = nil
) -> VNode {
    fieldControl(label: label, binding: text, type: type, placeholder: placeholder,
                 error: error, size: size, disabled: disabled,
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
    disabled: Bool = false,
    _ attributes: Attribute...
) -> VNode {
    fieldControl(label: label, binding: field.binding, type: type, placeholder: placeholder,
                 error: field.error, size: size, disabled: disabled,
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
    disabled: Bool,
    attributes: [Attribute],
    onBlur: (@MainActor () -> Void)?
) -> VNode {
    ensureBaseStyles()
    installControlSheet(id: "sw-field", fieldStyleSheet)

    let (callerClasses, callerRest) = splitClasses(attributes)

    var inputAttrs: [Attribute] = [
        .attr("type", type.attributeValue),
        .value(binding),
        .attr("aria-invalid", error != nil ? "true" : "false"),
    ]
    if !placeholder.isEmpty { inputAttrs.append(.attr("placeholder", placeholder)) }
    if disabled { inputAttrs.append(.attr("disabled", true)) }
    if let onBlur { inputAttrs.append(.on(.blur, perform: onBlur)) }
    if !callerClasses.isEmpty { inputAttrs.append(.class(callerClasses.joined(separator: " "))) }
    inputAttrs += callerRest   // caller wins on the input (type override, name, etc.)

    var rootChildren: [VNode] = [
        element("label", attributes: [.class("sw-field__label")], children: [
            element("span", attributes: [.class("sw-field__label-text")], children: [text(labelText)]),
            element("input", attributes: inputAttrs),
        ]),
    ]
    if let error {
        rootChildren.append(
            element("p", attributes: [.class("sw-field__error"), .attr("role", "alert")],
                    children: [text(error)])
        )
    }
    return element("div", attributes: [.class("sw-field sw-field--\(size.modifierClass)")],
                   children: rootChildren)
}

/// The shared global `.sw-field` stylesheet for the form controls (TextField now;
/// Select/Toggle/RadioGroup reuse the input/select base + error chrome). Injected
/// once; every value reads a `--sw-*` token so it reskins and honors the media
/// layers (reduced-motion via `--sw-duration`, contrast via `--sw-focus-ring`/
/// `--sw-border-width`, dark via `light-dark()`).
let fieldStyleSheet: CSSSheet = css {
    raw("""
    .sw-field {
      display: flex;
      flex-direction: column;
      gap: var(--sw-space-xs);
    }
    .sw-field__label {
      display: flex;
      flex-direction: column;
      gap: var(--sw-space-xs);
      font-size: 0.875rem;
      color: var(--sw-text);
    }
    .sw-field input,
    .sw-field select,
    .sw-field textarea {
      font: inherit;
      width: 100%;
      box-sizing: border-box;
      border: var(--sw-border-width) solid var(--sw-border);
      border-radius: var(--sw-radius);
      background-color: var(--sw-surface);
      color: var(--sw-text);
      transition: border-color var(--sw-duration) var(--sw-ease);
    }
    .sw-field input:focus-visible,
    .sw-field select:focus-visible,
    .sw-field textarea:focus-visible {
      outline: var(--sw-focus-ring-width) solid var(--sw-focus-ring);
      outline-offset: 2px;
      border-color: var(--sw-focus-ring);
    }
    .sw-field input:disabled,
    .sw-field select:disabled,
    .sw-field textarea:disabled {
      opacity: var(--sw-disabled-opacity);
      cursor: not-allowed;
    }
    .sw-field input[aria-invalid="true"],
    .sw-field select[aria-invalid="true"],
    .sw-field textarea[aria-invalid="true"] {
      border-color: var(--sw-danger);
    }
    .sw-field__error {
      margin: 0;
      font-size: 0.8125rem;
      color: var(--sw-danger);
    }

    /* sizes (padding + font come from the size modifier, not the base rule) */
    .sw-field--sm input, .sw-field--sm select, .sw-field--sm textarea { padding: var(--sw-space-xs) var(--sw-space-sm); font-size: 0.875rem; }
    .sw-field--md input, .sw-field--md select, .sw-field--md textarea { padding: var(--sw-space-sm) var(--sw-space-md); font-size: 1rem; }
    .sw-field--lg input, .sw-field--lg select, .sw-field--lg textarea { padding: var(--sw-space-md) var(--sw-space-lg); font-size: 1.125rem; }
    """)
}
