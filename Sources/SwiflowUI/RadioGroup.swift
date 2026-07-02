// Sources/SwiflowUI/RadioGroup.swift
import Swiflow

/// A single-choice radio group. Stateless free function over a native
/// `<fieldset>`/`<legend>` + N `<label>`-wrapped `<input type="radio">` rows that
/// share a `name` — which is what gives the group native roving focus + arrow-key
/// navigation for free (the reason this can stay a free function). One
/// `Binding<String>` drives the whole group: each radio's checked state is derived
/// (`selection == option.value`) and selecting a radio writes its value back.
///
/// Group-level concerns (error, `aria-invalid`/`aria-required`, `disabled`) live
/// on the `<fieldset>` (a disabled fieldset disables every radio natively); the
/// error tints the `<legend>` since a group has no single control to outline.
///
/// Reuses `SelectOption` (value/label; bare string literals make them equal). The
/// radio `name` defaults to a slug of `label`; pass `name:` explicitly if two
/// groups on the same page would otherwise collide. Caller `Attribute...`/`.class`
/// land on the `<fieldset>` (the group root).
///
///     RadioGroup("Plan", selection: $plan, options: ["Free", "Pro", "Team"])
///     RadioGroup("Role", field: roleField, options: [SelectOption("admin", "Administrator"), "Member"])
@MainActor
public func RadioGroup(
    _ label: String,
    selection: Binding<String>,
    options: [SelectOption],
    name: String? = nil,
    error: String? = nil,
    size: ControlSize = .md,
    required: Bool = false,
    disabled: Bool = false,
    _ attributes: Attribute...
) -> VNode {
    radioGroupControl(label: label, selection: selection, options: options,
                      name: name ?? radioGroupName(label), error: error, size: size, required: required,
                      disabled: disabled, attributes: attributes, onSelect: nil)
}

/// `Field`-integrated convenience. markTouched fires on SELECT (folded into the
/// per-option binding's setter) — not blur, which roves between radios in the
/// group; selecting is the honest "touched" signal for a radio group.
@MainActor
public func RadioGroup(
    _ label: String,
    field: Field<String>,
    options: [SelectOption],
    name: String? = nil,
    size: ControlSize = .md,
    required: Bool = false,
    disabled: Bool = false,
    _ attributes: Attribute...
) -> VNode {
    radioGroupControl(label: label, selection: field.binding, options: options,
                      name: name ?? radioGroupName(label), error: field.error, size: size, required: required,
                      disabled: disabled, attributes: attributes,
                      onSelect: { _ in field.markTouched() })
}

/// Slug a label into a stable radio `name` ("Favorite Color" → "favorite-color").
/// Stable across renders (same label → same name), unlike a counter — a changing
/// name would break grouping and reconciliation.
private func radioGroupName(_ label: String) -> String {
    let spaced = String(label.lowercased().map { ($0.isLetter || $0.isNumber) ? $0 : " " })
    let slug = spaced.split(separator: " ").joined(separator: "-")
    return slug.isEmpty ? "radiogroup" : slug
}

@MainActor
private func radioGroupControl(
    label labelText: String,
    selection: Binding<String>,
    options: [SelectOption],
    name: String,
    error: String?,
    size: ControlSize,
    required: Bool,
    disabled: Bool,
    attributes: [Attribute],
    onSelect: (@MainActor (String) -> Void)?
) -> VNode {
    ensureBaseStyles()
    installFieldStyles()

    var children: [VNode] = [
        element("legend", attributes: [.class("sw-radio__legend")], children: [text(labelText)]),
    ]
    for option in options {
        // Per-option Bool binding derived from the group's String selection. The
        // setter writes the value (and marks touched via onSelect) only when the
        // radio becomes checked; the native shared `name` clears the others.
        let optionBinding = Binding<Bool>(
            get: { selection.get() == option.value },
            set: { isChecked in
                if isChecked { selection.set(option.value); onSelect?(option.value) }
            }
        )
        children.append(
            element("label", attributes: [.class("sw-radio__option")], children: [
                element("input", attributes: [.attr("type", "radio"), .attr("name", name), .checked(optionBinding)]),
                element("span", attributes: [.class("sw-radio__option-label")], children: [text(option.label)]),
            ])
        )
    }
    if let errorNode = fieldErrorNode(error) { children.append(errorNode) }

    let groupAttrs = fieldGroupAttributes(["sw-radio", "sw-radio--\(size.modifierClass)"], error: error, required: required,
                                          disabled: disabled, caller: attributes)
    return element("fieldset", attributes: groupAttrs, children: children)
}
