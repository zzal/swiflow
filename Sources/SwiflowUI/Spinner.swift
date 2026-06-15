// Sources/SwiflowUI/Spinner.swift
import Swiflow

/// An indeterminate loading spinner. Stateless free function: a CSS ring that
/// rotates, marked `role="status"` with an `aria-label` so assistive tech
/// announces it. The rotation is gated on `animation-play-state: var(--sw-anim-play)`,
/// so `prefers-reduced-motion` freezes it with no per-component code (the exact
/// reason that token exists). Token-driven: accent ring on a `--sw-border` track,
/// `em`-sized so it scales with surrounding text.
///
///     Spinner()
///     Spinner(size: .lg, label: "Loading results")
@MainActor
public func Spinner(
    size: ControlSize = .md,
    label: String = "Loading",
    _ attributes: Attribute...
) -> VNode {
    ensureBaseStyles()
    installControlSheet(id: "sw-spinner", spinnerStyleSheet)

    let (callerClasses, callerRest) = splitClasses(attributes)
    let classValue = (["sw-spinner", "sw-spinner--\(size.modifierClass)"] + callerClasses)
        .joined(separator: " ")
    // `label` rides in a visually-hidden text child rather than `aria-label`: a
    // polite live region (role=status) announces text CONTENT changes, and a static
    // aria-label often isn't announced on insert. The text gives it real content.
    return element("span",
                   attributes: [.class(classValue), .attr("role", "status")] + callerRest,
                   children: [
                       element("span", attributes: [.class("sw-visually-hidden")], children: [text(label)]),
                   ])
}

let spinnerStyleSheet: CSSSheet = css {
    raw("""
    .sw-spinner {
      display: inline-block;
      box-sizing: border-box;
      border: 2px solid var(--sw-border);
      border-top-color: var(--sw-accent);
      border-radius: 50%;
      animation: sw-spin 0.7s linear infinite;
      animation-play-state: var(--sw-anim-play);   /* prefers-reduced-motion → paused */
    }
    .sw-spinner--sm { width: 1em; height: 1em; }
    .sw-spinner--md { width: 1.5em; height: 1.5em; }
    .sw-spinner--lg { width: 2.25em; height: 2.25em; border-width: 3px; }
    @keyframes sw-spin { to { transform: rotate(360deg); } }
    /* Standard sr-only: keeps the label in the a11y tree without visual footprint. */
    .sw-visually-hidden {
      position: absolute;
      width: 1px;
      height: 1px;
      margin: -1px;
      padding: 0;
      border: 0;
      overflow: hidden;
      clip: rect(0 0 0 0);
      clip-path: inset(50%);
      white-space: nowrap;
    }
    """)
}
