// Sources/SwiflowUI/Select.swift
import Swiflow

/// One choice in a `Select`. `value` is the form value bound to the selection;
/// `label` is the visible text. A bare string literal makes both the same
/// (`"Red"` → value & label `"Red"`); use `SelectOption("r", "Red")` when they differ.
public struct SelectOption: Equatable {
    public let value: String
    public let label: String
    public init(_ value: String, _ label: String) { self.value = value; self.label = label }
    public init(_ value: String) { self.value = value; self.label = value }
}

extension SelectOption: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self.init(value) }
}

/// A labelled dropdown. Stateless free function over a native `<select>` bound
/// with `.selection`, laid out in the shared `.sw-field` column chrome (label
/// above, `role="alert"` error below). Native `<select>` gives full keyboard +
/// listbox a11y for free; the appearance is skinned with the 2024+ Customizable
/// Select CSS (`appearance: base-select` — styles the control AND its dropdown
/// picker, all token-driven), with a `@supports` fallback for older browsers.
/// An optional `placeholder` prepends an empty-value first option. Caller
/// `Attribute...`/`.class` land on the `<select>` — don't pass `.selection`/
/// `.on(.change)` (they'd overwrite the binding; use `selection:`).
///
///     Select("Color", selection: $color, options: ["Red", "Green", "Blue"], placeholder: "Choose…")
///     Select("Role", field: roleField, options: [SelectOption("admin", "Administrator"), "Member"])
@MainActor
public func Select(
    _ label: String,
    selection: Binding<String>,
    options: [SelectOption],
    placeholder: String = "",
    error: String? = nil,
    size: ControlSize = .md,
    required: Bool = false,
    disabled: Bool = false,
    _ attributes: Attribute...,
    onBlur: (@MainActor () -> Void)? = nil
) -> VNode {
    selectControl(label: label, selection: selection, options: options, placeholder: placeholder,
                  error: error, size: size, required: required, disabled: disabled,
                  attributes: attributes, onBlur: onBlur)
}

/// `Field`-integrated convenience (mirrors `TextField(field:)`/`Toggle(field:)`):
/// wires the bound value, error + `aria-invalid`, and blur→`markTouched`.
@MainActor
public func Select(
    _ label: String,
    field: Field<String>,
    options: [SelectOption],
    placeholder: String = "",
    size: ControlSize = .md,
    required: Bool = false,
    disabled: Bool = false,
    _ attributes: Attribute...
) -> VNode {
    selectControl(label: label, selection: field.binding, options: options, placeholder: placeholder,
                  error: field.error, size: size, required: required, disabled: disabled,
                  attributes: attributes, onBlur: { field.markTouched() })
}

@MainActor
private func selectControl(
    label labelText: String,
    selection: Binding<String>,
    options: [SelectOption],
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

    let selectAttrs = controlInputAttributes([.selection(selection)], error: error, required: required,
                                             disabled: disabled, onBlur: onBlur, caller: attributes)

    // Mark the option matching the bound value as `selected` so the right option
    // renders at mount. The bound `value` *property* is applied before the <option>
    // children exist, so without `selected` the browser falls back to the first
    // option (the select-initial-value mount-order gotcha) — which loses any
    // non-first initial/persisted value.
    let current = selection.get()
    var optionNodes: [VNode] = []
    if !placeholder.isEmpty {
        // Empty-value first option; selecting it means "no choice" (fails `.required()`).
        var attrs: [Attribute] = [.attr("value", "")]
        if current.isEmpty { attrs.append(.attr("selected", "")) }
        optionNodes.append(element("option", attributes: attrs, children: [text(placeholder)]))
    }
    for option in options {
        var attrs: [Attribute] = [.attr("value", option.value)]
        if option.value == current { attrs.append(.attr("selected", "")) }
        optionNodes.append(element("option", attributes: attrs, children: [text(option.label)]))
    }

    var rootChildren: [VNode] = [
        element("label", attributes: [.class("sw-field__label")], children: [
            element("span", attributes: [.class("sw-field__label-text")], children: [text(labelText)]),
            element("select", attributes: selectAttrs, children: optionNodes),
        ]),
    ]
    if let errorNode = fieldErrorNode(error) { rootChildren.append(errorNode) }
    return element("div", attributes: [.class("sw-field sw-field--\(size.modifierClass)")],
                   children: rootChildren)
}
