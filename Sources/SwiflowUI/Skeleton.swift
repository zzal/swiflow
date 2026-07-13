// Sources/SwiflowUI/Skeleton.swift
import Swiflow

/// A stateless shimmering placeholder — Badge's shape (a skinned `<span>`) for
/// blocking out content that hasn't loaded yet (an avatar circle, a card
/// thumbnail, a line of text). Purely decorative (`aria-hidden="true"`): the
/// real content it stands in for supplies the accessible semantics once it
/// mounts, so a screen reader should skip the placeholder rather than
/// announce it. The shimmer is gated on `animation-play-state:
/// var(--sw-anim-play)` — the exact Spinner precedent — so
/// `prefers-reduced-motion` freezes it into a static block with no
/// per-component code.
///
///     Skeleton(width: "2.5em", height: "2.5em", radius: "50%")   // avatar circle
///     Skeleton(height: "1.25em")                                  // a title-sized bar
@MainActor
public func Skeleton(width: String = "100%", height: String = "1em",
                     radius: String? = nil, _ attributes: Attribute...) -> VNode {
    ensureBaseStyles()
    installControlSheet(id: "sw-skeleton", skeletonStyleSheet)

    let (callerClasses, callerRest) = splitClasses(attributes)
    let classValue = (["sw-skeleton"] + callerClasses).joined(separator: " ")
    var style: [Attribute] = [.style("width", width), .style("height", height)]
    if let radius { style.append(.style("border-radius", radius)) }
    return element("span",
                   attributes: [.class(classValue), .attr("aria-hidden", "true")] + style + callerRest)
}

/// Multi-line text placeholder: a `.sw-skeleton-text` flex column of `lines`
/// bars (the sheet shortens the last one to 60% width, mimicking how real
/// paragraph text trails off). `lines <= 0` renders an empty, still-decorative
/// container rather than trapping.
///
///     Skeleton(lines: 3)   // a paragraph-shaped loading placeholder
@MainActor
public func Skeleton(lines: Int, _ attributes: Attribute...) -> VNode {
    ensureBaseStyles()
    installControlSheet(id: "sw-skeleton", skeletonStyleSheet)

    let (callerClasses, callerRest) = splitClasses(attributes)
    let classValue = (["sw-skeleton-text"] + callerClasses).joined(separator: " ")
    let bars = (0..<max(0, lines)).map { _ in
        element("span", attributes: [.class("sw-skeleton")])
    }
    return element("div",
                   attributes: [.class(classValue), .attr("aria-hidden", "true")] + callerRest,
                   children: bars)
}

let skeletonStyleSheet: CSSSheet = css {
    raw("""
    .sw-skeleton {
      display: block;
      background-color: var(--sw-surface-2);
      background-image: linear-gradient(90deg, transparent, color-mix(in oklab, var(--sw-surface) 60%, transparent), transparent);
      background-size: 200% 100%;
      background-repeat: no-repeat;
      border-radius: var(--sw-radius-sm);
      animation: sw-skeleton-shimmer 1.4s ease-in-out infinite;
      animation-play-state: var(--sw-anim-play);   /* prefers-reduced-motion → paused (static block) */
    }
    @keyframes sw-skeleton-shimmer { from { background-position: 200% 0; } to { background-position: -200% 0; } }
    .sw-skeleton-text { display: flex; flex-direction: column; gap: var(--sw-space-xs); }
    .sw-skeleton-text > .sw-skeleton { height: 0.8em; }
    .sw-skeleton-text > .sw-skeleton:last-child { width: 60%; }
    """)
}
