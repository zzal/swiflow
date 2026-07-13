// Sources/SwiflowUI/Container.swift
import Swiflow

/// Max-width band of a `Container`: `.sm`/`.md`/`.lg`/`.xl` map onto the
/// `--sw-container-{sm,md,lg,xl}` tokens (Theme.swift; 30/60/90/120ch by default,
/// i.e. character-measure widths for readable line lengths — re-point them to
/// retheme every `Container` in an app at once). Maps to a `sw-container--<variant>`
/// class (Badge's shape).
public enum ContainerSize: Equatable {
    case sm, md, lg, xl
    var modifierClass: String {
        switch self {
        case .sm: return "sm"
        case .md: return "md"
        case .lg: return "lg"
        case .xl: return "xl"
        }
    }
}

/// The simplest layout primitive: a stateless centered max-width `<div>` — the
/// page shell most apps wrap their content in. `margin-inline: auto` centers it
/// once it hits its `max-width`; `padding-inline` keeps content off the viewport
/// edge below that width. Caller `Attribute...`/`.class` merge onto the root.
///
///     Container { Text("Page content") }        // .lg by default
///     Container(size: .sm) { LoginForm() }
@MainActor
public func Container(
    size: ContainerSize = .lg,
    _ attributes: Attribute...,
    @ChildrenBuilder content: () -> [VNode]
) -> VNode {
    ensureBaseStyles()
    installControlSheet(id: "sw-container", containerStyleSheet)

    let (callerClasses, callerRest) = splitClasses(attributes)
    let classValue = (["sw-container", "sw-container--\(size.modifierClass)"] + callerClasses)
        .joined(separator: " ")
    return element("div", attributes: [.class(classValue)] + callerRest, children: content())
}

let containerStyleSheet: CSSSheet = css {
    raw("""
    .sw-container { width: 100%; margin-inline: auto; padding-inline: var(--sw-space-md); box-sizing: border-box; }
    .sw-container--sm { max-width: var(--sw-container-sm); }
    .sw-container--md { max-width: var(--sw-container-md); }
    .sw-container--lg { max-width: var(--sw-container-lg); }
    .sw-container--xl { max-width: var(--sw-container-xl); }
    """)
}
