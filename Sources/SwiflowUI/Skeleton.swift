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
    /* The skeleton BLENDS with its backdrop — multiply in light mode (darkens
       whatever it sits on), screen in dark mode (lightens it) — so placeholders
       harmonize with tinted/colored surfaces instead of painting flat gray.

       mix-blend-mode is a keyword, so it can't ride light-dark() and a
       prefers-color-scheme media query wouldn't follow a forced root
       `color-scheme` (this kit's toggle seam). Instead: TWO stacked layers with
       constant keywords whose PAINT self-neutralizes in the wrong scheme —
       multiply by white and screen by black are both identity, and the paints
       are plain light-dark() colors:

         ::before  multiply  light-dark(gray,  #fff)   ← active in light
         ::after   screen    light-dark(#000,  gray)   ← active in dark

       The element itself paints nothing and must NOT form a stacking context
       (position: relative + z-index auto is fine) so the pseudos blend against
       the real backdrop, not an isolated black/white layer. */
    .sw-skeleton {
      display: block;
      position: relative;
      border-radius: var(--sw-radius-sm);
    }
    .sw-skeleton::before,
    .sw-skeleton::after {
      content: "";
      position: absolute;
      inset: 0;
      border-radius: inherit;
      background-size: 200% 100%;
      background-repeat: no-repeat;
      animation: sw-skeleton-shimmer 1.4s ease-in-out infinite;
      animation-play-state: var(--sw-anim-play);   /* prefers-reduced-motion → paused (static block) */
    }
    .sw-skeleton::before {
      mix-blend-mode: multiply;
      background-color: light-dark(var(--sw-surface-2), #fff);
      background-image: linear-gradient(90deg, transparent,
          light-dark(color-mix(in oklab, #fff 60%, transparent), transparent), transparent);
    }
    .sw-skeleton::after {
      mix-blend-mode: screen;
      background-color: light-dark(#000, var(--sw-surface-2));
      background-image: linear-gradient(90deg, transparent,
          light-dark(transparent, color-mix(in oklab, #fff 12%, transparent)), transparent);
    }
    @keyframes sw-skeleton-shimmer { from { background-position: 200% 0; } to { background-position: -200% 0; } }
    .sw-skeleton-text { display: flex; flex-direction: column; gap: var(--sw-space-xs); }
    .sw-skeleton-text > .sw-skeleton { height: 0.8em; }
    .sw-skeleton-text > .sw-skeleton:last-child { width: 60%; }
    """)
}
