// Sources/SwiflowUI/Button.swift
import Swiflow

/// Visual style of a `Button`. `.primary` is an accent fill, `.secondary` a
/// bordered surface, `.ghost` a transparent text button, `.danger` a
/// destructive solid fill on the danger token family (delete/remove
/// confirms — Badge/Toast/DropdownItem already speak danger; buttons now
/// do too). Maps to a `sw-btn--<variant>` modifier class whose declarations
/// live in the shared button stylesheet — every value reads a `--sw-*`
/// token, so variants reskin (and respond to the media-feature layers)
/// with no API change.
public enum ButtonVariant: Equatable {
    case primary, secondary, ghost, danger
    /// The `sw-btn--<variant>` modifier-class token.
    var modifierClass: String {
        switch self {
        case .primary:   return "primary"
        case .secondary: return "secondary"
        case .ghost:     return "ghost"
        case .danger:    return "danger"
        }
    }
}

/// A skinned button. Renders a native `<button type="button">` carrying the
/// `sw-btn` utility classes; the one-time-injected stylesheet does the styling,
/// reading only `--sw-*` tokens. Native semantics give keyboard + role for free
/// (native-leaning a11y); `:focus-visible`/`:disabled` read the focus-ring and
/// disabled-opacity tokens, and the `transition` reads the motion tokens, so the
/// M2 media-feature layers (contrast, reduced-motion, …) apply automatically.
///
/// Caller `Attribute...` apply last (last-write-wins) so they can override
/// `type` etc.; a caller `.class(_:)` is MERGED with the skin classes rather
/// than clobbering them (see `splitClasses`). SwiflowUI reserves the `sw-` class
/// prefix — don't author app CSS under it.
///
/// `action` is deliberately a *labeled* trailing closure so the
/// `@ChildrenBuilder` label overloads below (icon + text) take the unlabeled
/// trailing-closure slot without breaking callers — the seat M4 reserved,
/// now filled.
///
///     Button("Save") { store.save() }
///     Button("Delete", variant: .ghost, size: .sm, disabled: !canDelete) { delete() }
@MainActor
public func Button(
    _ title: String,
    variant: ButtonVariant = .primary,
    size: ControlSize = .md,
    disabled: Bool = false,
    _ attributes: Attribute...,
    action: @escaping @MainActor () -> Void
) -> VNode {
    buttonNode([text(title)], variant: variant, size: size, disabled: disabled,
               type: .button, attributes: attributes, action: action)
}

/// Builder-label variant — compose the label from any VNodes (icon + text,
/// badges, …). `.sw-btn` is `inline-flex` with the spacing-token gap, so
/// children lay out without extra CSS. Icons are plain VNodes (a masked
/// `span`, an SVG, an emoji) — mark decorative ones `aria-hidden`.
///
/// > Accessibility: an icon-ONLY label leaves the button with no accessible
/// > name — pass `.attr("aria-label", …)` (DEBUG builds warn if you forget).
///
///     Button(variant: .danger, action: { delete() }) { trashIcon(); text("Delete") }
///     Button(.attr("aria-label", "Close"), action: { close() }) { closeIcon() }
@MainActor
public func Button(
    variant: ButtonVariant = .primary,
    size: ControlSize = .md,
    disabled: Bool = false,
    _ attributes: Attribute...,
    action: @escaping @MainActor () -> Void,
    @ChildrenBuilder label: () -> [VNode]
) -> VNode {
    buttonNode(label(), variant: variant, size: size, disabled: disabled,
               type: .button, attributes: attributes, action: action)
}

/// The native `<button>` `type`. `.submit`/`.reset` belong to a `<form>` and carry
/// **no** click action — the enclosing form owns the behavior.
public enum ButtonType: String { case button, submit, reset }

/// Form-button variant: renders `type="submit"`/`"reset"` with **no** click handler,
/// because the enclosing `<form>` drives the action (e.g. a `Prompt`'s confirm button,
/// where the form's `submit` is the single source of truth). No trailing closure — a
/// submit button conceptually has no action of its own.
///
///     Button("Rename", type: .submit)   // inside a <form method="dialog">
@MainActor
public func Button(
    _ title: String,
    variant: ButtonVariant = .primary,
    size: ControlSize = .md,
    disabled: Bool = false,
    type: ButtonType,
    _ attributes: Attribute...
) -> VNode {
    buttonNode([text(title)], variant: variant, size: size, disabled: disabled,
               type: type, attributes: attributes, action: nil)
}

/// Builder-label twin of the form-button variant: `type: .submit`/`.reset`
/// with a composed label and no click handler (the form drives it).
///
///     Button(type: .submit) { checkIcon(); text("Save") }
@MainActor
public func Button(
    variant: ButtonVariant = .primary,
    size: ControlSize = .md,
    disabled: Bool = false,
    type: ButtonType,
    _ attributes: Attribute...,
    @ChildrenBuilder label: () -> [VNode]
) -> VNode {
    buttonNode(label(), variant: variant, size: size, disabled: disabled,
               type: type, attributes: attributes, action: nil)
}

/// Shared lowering. `action == nil` ⇒ no click handler is registered (form buttons).
@MainActor
private func buttonNode(
    _ label: [VNode],
    variant: ButtonVariant,
    size: ControlSize,
    disabled: Bool,
    type: ButtonType,
    attributes: [Attribute],
    action: (@MainActor () -> Void)?
) -> VNode {
    ensureBaseStyles()
    installControlSheet(id: "sw-button", buttonStyleSheet)

    let (callerClasses, callerRest) = splitClasses(attributes)
    let classValue = (["sw-btn", "sw-btn--\(variant.modifierClass)", "sw-btn--\(size.modifierClass)"]
        + callerClasses).joined(separator: " ")

    var attrs: [Attribute] = [.class(classValue), .attr("type", type.rawValue)]
    if disabled {
        attrs.append(.attr("disabled", true))           // no click handler on a disabled button
    } else if let action {
        attrs.append(.on(.click, perform: action))      // submit/reset pass nil → no handler; the form drives them
    }
    attrs += callerRest   // caller wins on everything except the merged class

    #if DEBUG
    // A11y guardrail (audit V Wave-2 #7): a label with no text content
    // anywhere leaves the button with NO accessible name unless the caller
    // supplied aria-label. String-titled buttons always pass (their label
    // is a text node); only composed icon-only labels can trip this.
    if !containsTextContent(label), !hasAriaLabel(attributes) {
        swiflowWarn(
            "Button: icon-only label has no accessible name — add "
                + ".attr(\"aria-label\", \"…\") or include text in the label."
        )
    }
    #endif

    return element("button", attributes: attrs, children: label)
}

#if DEBUG
/// Does any node in the subtree carry non-whitespace text?
@MainActor
private func containsTextContent(_ nodes: [VNode]) -> Bool {
    for node in nodes {
        switch node {
        case .text(let s):
            if s.contains(where: { !$0.isWhitespace }) { return true }   // Foundation-free
        case .element(let data):
            if containsTextContent(data.children) { return true }
        case .fragment(let children):
            if containsTextContent(children) { return true }
        default:
            continue
        }
    }
    return false
}

/// Did the caller provide an aria-label (directly or inside a .compound)?
@MainActor
private func hasAriaLabel(_ attributes: [Attribute]) -> Bool {
    attributes.contains { attribute in
        switch attribute {
        case .attribute(let name, _) where name == "aria-label": return true
        case .compound(let inner): return hasAriaLabel(inner)
        default: return false
        }
    }
}
#endif

/// The global `.sw-btn` stylesheet, injected once. Authored raw because these are
/// unscoped utility classes (not per-instance scoped styles) — every value reads
/// a token so the whole sheet reskins from `:root` and honors the media layers.
let buttonStyleSheet: CSSSheet = css {
    raw("""
    .sw-btn {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      gap: var(--sw-space-sm);
      border: var(--sw-border-width) solid transparent;
      border-radius: var(--sw-radius);
      font: inherit;
      font-weight: 500;
      line-height: 1.2;
      cursor: pointer;
      transition: background-color var(--sw-duration) var(--sw-ease),
                  border-color var(--sw-duration) var(--sw-ease),
                  color var(--sw-duration) var(--sw-ease),
                  box-shadow var(--sw-duration) var(--sw-ease);
    }
    .sw-btn:focus-visible {
      outline: 2px solid transparent;   /* keeps a visible focus under forced-colors */
      box-shadow: var(--sw-focus-shadow);
    }
    .sw-btn:disabled {
      opacity: var(--sw-disabled-opacity);
      cursor: not-allowed;
    }

    /* sizes */
    .sw-btn--xs { padding: 0.125rem var(--sw-space-xs); font-size: 0.8125rem; }
    .sw-btn--sm { padding: var(--sw-space-xs) var(--sw-space-sm); font-size: 0.875rem; }
    .sw-btn--md { padding: var(--sw-space-sm) var(--sw-space-md); font-size: 1rem; }
    .sw-btn--lg { padding: var(--sw-space-md) var(--sw-space-lg); font-size: 1.125rem; }

    /* variants — hover/active read dedicated tokens so they stay dark-mode-correct */
    .sw-btn--primary {
      background-color: var(--sw-accent);
      color: var(--sw-accent-text);
    }
    .sw-btn--primary:hover:not(:disabled)  { background-color: var(--sw-accent-hover); }
    .sw-btn--primary:active:not(:disabled) { background-color: var(--sw-accent-active); }
    .sw-btn--secondary {
      background-color: var(--sw-surface);
      color: var(--sw-text);
      border-color: var(--sw-border);
    }
    .sw-btn--secondary:hover:not(:disabled),
    .sw-btn--secondary:active:not(:disabled) { background-color: var(--sw-surface-2); }
    .sw-btn--ghost {
      background-color: transparent;
      color: var(--sw-accent);
    }
    .sw-btn--ghost:hover:not(:disabled),
    .sw-btn--ghost:active:not(:disabled) { background-color: var(--sw-surface-2); }
    .sw-btn--danger {
      background-color: var(--sw-danger);
      color: var(--sw-danger-text);
    }
    .sw-btn--danger:hover:not(:disabled)  { background-color: var(--sw-danger-hover); }
    .sw-btn--danger:active:not(:disabled) { background-color: var(--sw-danger-active); }
    """)
}
