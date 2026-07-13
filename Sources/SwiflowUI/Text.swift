// Sources/SwiflowUI/Text.swift
import Swiflow

/// The visual role of a `Text` — picks both the type-scale styling and the
/// semantic HTML tag it renders as by default (override with `tag:`).
public enum TextVariant: Equatable {
    case title, heading, subheading, body, caption, label

    var modifierClass: String {
        switch self {
        case .title:      return "title"
        case .heading:     return "heading"
        case .subheading: return "subheading"
        case .body:        return "body"
        case .caption:     return "caption"
        case .label:       return "label"
        }
    }

    /// The semantic element rendered when the caller doesn't pass `tag:`.
    /// `.caption` shares `.body`'s `<p>` (a caption is still a paragraph,
    /// just smaller); `.label` renders `<span>` since it's typically inline
    /// alongside a control rather than a block of its own.
    var defaultTag: String {
        switch self {
        case .title:      return "h1"
        case .heading:     return "h2"
        case .subheading: return "h3"
        case .body:        return "p"
        case .caption:     return "p"
        case .label:       return "span"
        }
    }
}

/// An explicit font-weight override. `nil` (the default on `Text`) defers to
/// the variant's own weight from the sheet below.
public enum TextWeight: Equatable {
    case regular, medium, semibold

    var modifierClass: String {
        switch self {
        case .regular:  return "regular"
        case .medium:   return "medium"
        case .semibold: return "semibold"
        }
    }
}

/// Text color. `.standard` is the default body-text token and emits no
/// modifier class (the base `.sw-text` rule already sets it); the rest map to
/// the matching semantic token's `-strong` variant — the mid-tone base token
/// fails WCAG as light-mode text (the Badge lesson), `-strong` doesn't.
public enum TextColor: Equatable {
    case standard, muted, accent, danger, success, warning

    var modifierClass: String? {
        switch self {
        case .standard: return nil
        case .muted:    return "muted"
        case .accent:   return "accent"
        case .danger:   return "danger"
        case .success:  return "success"
        case .warning:  return "warning"
        }
    }
}

/// A stateless typography primitive over the type-scale tokens (`--sw-font-size-*`,
/// `--sw-font-weight-*`, `--sw-line-height*`). Renders as the variant's semantic
/// tag by default (`title`→`h1`, `heading`→`h2`, `subheading`→`h3`, `body`/`caption`→`p`,
/// `label`→`span`) — pass `tag:` to render a different element while keeping the
/// variant's visual styling, e.g. an `h1`-styled `title` inside a `<header>` that
/// itself renders the real page `h1`.
///
/// Named `Text` (capitalized), not `text` — the DSL's text-node factory is the
/// lowercase `text(_:)` (`Sources/Swiflow/DSL/Elements.swift`); Swift is
/// case-sensitive so there's no collision. There's no SwiftUI/Foundation `Text`
/// on wasm to shadow either.
///
///     Text("Page title", variant: .title)
///     Text("Section", variant: .heading, tag: "h1")   // styled as heading, but the page's only h1
///     Text("Fine print", variant: .caption, color: .muted)
///     Text("Error", color: .danger, weight: .semibold)
@MainActor
public func Text(
    _ content: String,
    variant: TextVariant = .body,
    weight: TextWeight? = nil,
    color: TextColor = .standard,
    tag: String? = nil,
    _ attributes: Attribute...
) -> VNode {
    ensureBaseStyles()
    installControlSheet(id: "sw-text", textStyleSheet)

    let (callerClasses, callerRest) = splitClasses(attributes)
    let classValue = (
        ["sw-text", "sw-text--\(variant.modifierClass)"]
        + (weight.map { ["sw-text--w-\($0.modifierClass)"] } ?? [])
        + (color.modifierClass.map { ["sw-text--c-\($0)"] } ?? [])
        + callerClasses
    ).joined(separator: " ")

    return element(tag ?? variant.defaultTag, attributes: [.class(classValue)] + callerRest, children: [text(content)])
}

let textStyleSheet: CSSSheet = css {
    raw("""
    .sw-text { margin: 0; color: var(--sw-text); line-height: var(--sw-line-height); }
    .sw-text--title      { font-size: var(--sw-font-size-2xl); font-weight: var(--sw-font-weight-semibold); line-height: var(--sw-line-height-tight); }
    .sw-text--heading    { font-size: var(--sw-font-size-xl);  font-weight: var(--sw-font-weight-semibold); line-height: var(--sw-line-height-tight); }
    .sw-text--subheading { font-size: var(--sw-font-size-lg);  font-weight: var(--sw-font-weight-medium);   line-height: var(--sw-line-height-tight); }
    .sw-text--body       { font-size: var(--sw-font-size-md);  font-weight: var(--sw-font-weight-regular); }
    .sw-text--caption    { font-size: var(--sw-font-size-sm);  font-weight: var(--sw-font-weight-regular); }
    .sw-text--label      { font-size: var(--sw-font-size-sm);  font-weight: var(--sw-font-weight-medium); }
    .sw-text--w-regular  { font-weight: var(--sw-font-weight-regular); }
    .sw-text--w-medium   { font-weight: var(--sw-font-weight-medium); }
    .sw-text--w-semibold { font-weight: var(--sw-font-weight-semibold); }
    .sw-text--c-muted    { color: var(--sw-text-muted); }
    .sw-text--c-accent   { color: var(--sw-accent-strong); }
    .sw-text--c-danger   { color: var(--sw-danger-strong); }
    .sw-text--c-success  { color: var(--sw-success-strong); }
    .sw-text--c-warning  { color: var(--sw-warning-strong); }
    """)
}
