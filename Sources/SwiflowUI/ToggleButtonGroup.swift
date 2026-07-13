// Sources/SwiflowUI/ToggleButtonGroup.swift
import Swiflow

/// A segmented control of toggle buttons — `role="group"` of native
/// `<button type="button" aria-pressed>`, String-keyed like `RadioGroup`/`Select`
/// (`options: [String]`, id == label). Two overloads share one private lowering:
///
///     ToggleButtonGroup(selection: $align, options: ["left", "center", "right"])           // single: exactly one pressed
///     ToggleButtonGroup(selection: $formats, options: ["bold", "italic", "underline"])     // multi: toggles Set membership
///
/// `aria-pressed` is the WAI-ARIA "toggle button" pattern — valid for both a
/// single pressed button and several simultaneously-pressed buttons, unlike
/// `role="radio"`/`aria-checked` which implies exactly one. **No roving focus**:
/// each button keeps its own place in Tab order (the APG toggle-button pattern
/// doesn't mandate roving, and skipping it keeps this a stateless free function
/// with no mount identity to own an active index). For strict single-select
/// *with* roving focus, reach for `RadioGroup` (native radio roving) or `Tabs`
/// (tablist roving) instead — this control is deliberately the simpler sibling.
///
/// Stateless free function; caller `Attribute...`/`.class` land on the `role="group"`
/// div (the group root).
@MainActor
public func ToggleButtonGroup(
    selection: Binding<String>,
    options: [String],
    _ attributes: Attribute...
) -> VNode {
    toggleGroup(options: options,
                pressed: { selection.get() == $0 },
                onTap: { selection.set($0) },
                caller: attributes)
}

/// Multi-select overload: `selection` is the `Set` of currently-pressed option
/// labels; tapping a button toggles its membership (add if absent, remove if
/// present). See the single-select overload's doc comment for the shared shape.
@MainActor
public func ToggleButtonGroup(
    selection: Binding<Set<String>>,
    options: [String],
    _ attributes: Attribute...
) -> VNode {
    toggleGroup(options: options,
                pressed: { selection.get().contains($0) },
                onTap: { option in
                    var members = selection.get()
                    if members.contains(option) { members.remove(option) } else { members.insert(option) }
                    selection.set(members)
                },
                caller: attributes)
}

/// The shared lowering both overloads call: `pressed(option)` decides
/// `aria-pressed`, `onTap(option)` fires on click. Neither overload's identity
/// (single vs. multi) survives past this point — it's just booleans and a
/// tap callback from here down.
@MainActor
private func toggleGroup(
    options: [String],
    pressed: (String) -> Bool,
    onTap: @escaping (String) -> Void,
    caller: [Attribute]
) -> VNode {
    ensureBaseStyles()
    installControlSheet(id: "sw-togglegroup", toggleButtonGroupStyleSheet)

    let buttons: [VNode] = options.map { option in
        element("button", attributes: [
            .class("sw-togglegroup__btn"),
            .attr("type", "button"),
            .attr("aria-pressed", pressed(option) ? "true" : "false"),
            .on(.click) { onTap(option) },
        ], children: [text(option)])
    }

    let (callerClasses, callerRest) = splitClasses(caller)
    let rootClass = (["sw-togglegroup"] + callerClasses).joined(separator: " ")
    return element("div", attributes: [.class(rootClass), .attr("role", "group")] + callerRest, children: buttons)
}

let toggleButtonGroupStyleSheet: CSSSheet = css {
    raw("""
    .sw-togglegroup { display: inline-flex; }
    .sw-togglegroup__btn {
      appearance: none; cursor: pointer; font: inherit;
      padding: var(--sw-space-sm) var(--sw-space-md);
      background-color: var(--sw-surface); color: var(--sw-text);
      border: var(--sw-border-width) solid var(--sw-border);
      border-inline-start-width: 0;
    }
    .sw-togglegroup__btn:first-child { border-inline-start-width: var(--sw-border-width); border-start-start-radius: var(--sw-radius); border-end-start-radius: var(--sw-radius); }
    .sw-togglegroup__btn:last-child  { border-start-end-radius: var(--sw-radius); border-end-end-radius: var(--sw-radius); }
    .sw-togglegroup__btn[aria-pressed="true"] { background-color: var(--sw-accent); color: var(--sw-accent-text); border-color: var(--sw-accent); }
    .sw-togglegroup__btn:focus-visible { outline: var(--sw-focus-ring-width) solid var(--sw-focus-ring); outline-offset: -1px; z-index: 1; }
    """)
}
