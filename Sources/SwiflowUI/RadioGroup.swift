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
/// > Warning: two `RadioGroup`s sharing a native `name` (e.g. two "Role"
/// > pickers in different components — the name defaults to a label slug)
/// > share roving-focus/selection state at the DOM level: checking a radio
/// > in one group visually "checks" the matching-value radio in the other,
/// > and arrow-key roving crosses between them. DEBUG builds now DETECT
/// > this: an invisible mount sentinel registers each group's name, and a
/// > collision logs a warning naming both groups (see `RadioNameRegistry`).
/// > The fix is an explicit `name:` on one of the colliding groups.
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
    fieldSlug(label, fallback: "radiogroup")
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
                // The drawn dot (the input is sr-only-hidden; see .sw-radio in FieldChrome).
                // Presentational only — state/AT live on the input.
                element("span", attributes: [.class("sw-radio__dot"), .attr("aria-hidden", "true")], children: []),
                element("span", attributes: [.class("sw-radio__option-label")], children: [text(option.label)]),
            ])
        )
    }
    if let errorNode = fieldErrorNode(error) { children.append(errorNode) }

    #if DEBUG
    // Mount sentinel (audit V Wave-1): gives this stateless free function
    // the lifecycle identity the collision registry needs. Renders nothing;
    // DEBUG-only, so the release tree carries no extra node.
    children.append(embed { RadioNameSentinel(name: name, label: labelText) })
    #endif

    let groupAttrs = fieldGroupAttributes(["sw-radio", "sw-radio--\(size.modifierClass)"], error: error, required: required,
                                          disabled: disabled, caller: attributes)
    return element("fieldset", attributes: groupAttrs, children: children)
}

#if DEBUG
/// DEBUG-only, invisible mount sentinel embedded in every `RadioGroup`
/// fieldset. `RadioGroup` itself is a stateless free function — it has no
/// mount/unmount identity — so this component's lifecycle IS the group's
/// registration window: `onAppear` registers the native radio `name`,
/// `onDisappear` unregisters. Catches late-mounted collisions (conditional
/// rendering) and never false-positives on re-renders (the instance
/// persists; `onAppear` fires once). Dev tree ≠ release tree by exactly
/// this leaf — accepted, documented trade-off.
@Component
final class RadioNameSentinel {
    let name: String
    let label: String
    init(name: String, label: String) {
        self.name = name
        self.label = label
    }
    var body: VNode { .text("") }
    func onAppear() {
        RadioNameRegistry.register(name: name, label: label, id: ObjectIdentifier(self))
    }
    func onDisappear() {
        RadioNameRegistry.unregister(name: name, id: ObjectIdentifier(self))
    }
}

/// The live owners of each native radio `name`, keyed by sentinel instance
/// identity — an HMR swap or remount can never double-count itself into a
/// false positive (a count could).
@MainActor
enum RadioNameRegistry {
    static var owners: [String: [(id: ObjectIdentifier, label: String)]] = [:]

    static func register(name: String, label: String, id: ObjectIdentifier) {
        var list = owners[name] ?? []
        if let first = list.first(where: { $0.id != id }) {
            swiflowWarn(
                "RadioGroup name collision: \"\(label)\" and \"\(first.label)\" both render "
                    + "radios under the native name '\(name)' — selection and arrow-key "
                    + "roving will cross between them at the DOM level. Pass an explicit "
                    + "name: on one to keep the groups independent."
            )
        }
        if !list.contains(where: { $0.id == id }) {
            list.append((id: id, label: label))
        }
        owners[name] = list
    }

    static func unregister(name: String, id: ObjectIdentifier) {
        owners[name]?.removeAll { $0.id == id }
        if owners[name]?.isEmpty == true { owners[name] = nil }
    }

    /// Test seam — suites sharing the process-global registry reset it
    /// per test (and stay `.serialized`, the one-suite-owns-a-global-seam
    /// lesson from the @Persisted registry).
    static func _reset() { owners = [:] }
}
#endif
