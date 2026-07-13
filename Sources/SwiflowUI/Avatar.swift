// Sources/SwiflowUI/Avatar.swift
import Swiflow

/// The corner treatment of an `Avatar`. Maps to a `sw-avatar--<shape>` class.
public enum AvatarShape: Equatable {
    case circle, rounded, square
    var modifierClass: String {
        switch self {
        case .circle:  return "circle"
        case .rounded: return "rounded"
        case .square:  return "square"
        }
    }
}

/// A user/entity picture — Badge's shape, sized via `ControlSize` — that falls
/// back to initials when there's no image. With `src`, renders an `<img>`
/// (the URL folds through `URLSanitizer` via `.src`, exactly like `TextLink`'s
/// `href`: a `javascript:` src is neutralized). Without `src`, renders a
/// `<span role="img" aria-label=name>` filled with `avatarInitials(name)` —
/// the `role`/`aria-label` pair stands in for the missing `alt` text an
/// `<img>` would otherwise carry.
///
/// There's no automatic image-load-error fallback (e.g. swapping to initials
/// when `src` 404s) — that would need a load-failure signal this stateless
/// free function has no seam for, and it'd add a dependency this component
/// deliberately avoids. An app that needs it can track the failure itself and
/// pass `src: nil` (or a different `name`) once it observes one.
///
///     Avatar("Ada Lovelace", src: "https://example.com/ada.png")
///     Avatar("Ada Lovelace")                     // "AL" initials
///     Avatar("Grace Hopper", size: .lg, shape: .rounded)
@MainActor
public func Avatar(_ name: String, src: String? = nil, size: ControlSize = .md,
                   shape: AvatarShape = .circle, _ attributes: Attribute...) -> VNode {
    ensureBaseStyles()
    installControlSheet(id: "sw-avatar", avatarStyleSheet)

    let (callerClasses, callerRest) = splitClasses(attributes)
    let base = ["sw-avatar", "sw-avatar--\(size.modifierClass)", "sw-avatar--\(shape.modifierClass)"]

    if let src {
        let classValue = (base + callerClasses).joined(separator: " ")
        return element("img", attributes: [.class(classValue), .src(src), .alt(name)] + callerRest)
    }

    let classValue = (base + ["sw-avatar--initials"] + callerClasses).joined(separator: " ")
    return element("span",
                   attributes: [.class(classValue), .attr("role", "img"), .attr("aria-label", name)] + callerRest,
                   children: [text(avatarInitials(name))])
}

/// The first letter of the first up-to-two whitespace-separated words in
/// `name`, uppercased (e.g. "Ada Lovelace" → "AL", "Ada" → "A"). An
/// empty/whitespace-only `name` renders "?" rather than an empty label.
func avatarInitials(_ name: String) -> String {
    let words = name.split(whereSeparator: { $0.isWhitespace })
    guard !words.isEmpty else { return "?" }
    return words.prefix(2).compactMap { $0.first }.map { String($0).uppercased() }.joined()
}

let avatarStyleSheet: CSSSheet = css {
    raw("""
    .sw-avatar {
      display: inline-flex; align-items: center; justify-content: center;
      flex: none; overflow: hidden; object-fit: cover;
      background-color: var(--sw-surface-2); color: var(--sw-text-muted);
      font-weight: var(--sw-font-weight-medium); user-select: none;
    }
    .sw-avatar--sm { width: 2rem;   height: 2rem;   font-size: 0.75rem; }
    .sw-avatar--md { width: 2.5rem; height: 2.5rem; font-size: 0.875rem; }
    .sw-avatar--lg { width: 3rem;   height: 3rem;   font-size: 1rem; }
    .sw-avatar--circle  { border-radius: 50%; }
    .sw-avatar--rounded { border-radius: var(--sw-radius); }
    .sw-avatar--square  { border-radius: 0; }
    """)
}
