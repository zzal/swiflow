// Sources/SwiflowUI/Button.swift
import Swiflow

/// Visual style of a `Button`. `.primary` is an accent fill, `.secondary` a
/// bordered surface, `.ghost` a transparent text button. Maps to a
/// `sw-btn--<variant>` modifier class whose declarations live in the shared
/// button stylesheet — every value reads a `--sw-*` token, so variants reskin
/// (and respond to the media-feature layers) with no API change.
public enum ButtonVariant: Equatable {
    case primary, secondary, ghost
    /// The `sw-btn--<variant>` modifier-class token.
    public var modifierClass: String {
        switch self {
        case .primary:   return "primary"
        case .secondary: return "secondary"
        case .ghost:     return "ghost"
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
/// The label is a `String` for v1; `action` is deliberately a *labeled* trailing
/// closure so a future `@ChildrenBuilder` label overload (icon + text) can take
/// the unlabeled trailing-closure slot without breaking callers.
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
    ensureBaseStyles()
    installControlSheet(id: "sw-button", buttonStyleSheet)

    let (callerClasses, callerRest) = splitClasses(attributes)
    let classValue = (["sw-btn", "sw-btn--\(variant.modifierClass)", "sw-btn--\(size.modifierClass)"]
        + callerClasses).joined(separator: " ")

    var attrs: [Attribute] = [.class(classValue), .attr("type", "button")]
    if disabled {
        attrs.append(.attr("disabled", true))   // no click handler on a disabled button
    } else {
        attrs.append(.on(.click, perform: action))
    }
    attrs += callerRest   // caller wins on everything except the merged class

    return element("button", attributes: attrs, children: [text(title)])
}

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
                  color var(--sw-duration) var(--sw-ease);
    }
    .sw-btn:focus-visible {
      outline: var(--sw-focus-ring-width) solid var(--sw-focus-ring);
      outline-offset: 2px;
    }
    .sw-btn:disabled {
      opacity: var(--sw-disabled-opacity);
      cursor: not-allowed;
    }

    /* sizes */
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
    """)
}
