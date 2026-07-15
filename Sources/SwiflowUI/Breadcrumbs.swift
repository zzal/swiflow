// Sources/SwiflowUI/Breadcrumbs.swift
import Swiflow

/// One entry in a `Breadcrumbs` trail. `href == nil` renders a non-link crumb
/// (plain text) — used for a middle segment that has no navigable destination
/// of its own. The LAST crumb in a trail is always rendered as plain text with
/// `aria-current="page"`, even when it carries an `href`: the current page is
/// never a link to itself.
public struct Crumb {
    public let label: String
    public let href: String?

    public init(_ label: String, href: String? = nil) {
        self.label = label
        self.href = href
    }
}

/// A `<nav aria-label="Breadcrumb">` + `<ol>` trail. Stateless free function,
/// like `Badge`/`TextLink`. Deliberately does NOT depend on `SwiflowRouter`:
/// every linked crumb is a plain sanitized `<a>` (the `.href` DSL modifier
/// folds through `URLSanitizer`), never the Router `Link` — SwiflowUI stays
/// usable without a router. An app that wants in-app (SPA) navigation for its
/// crumbs supplies its own `<a>`/`Link` wrapper; `Breadcrumbs` itself stays
/// framework-agnostic.
///
/// The LAST crumb is always the current page: rendered as a `<span
/// aria-current="page">`, never an `<a>`, regardless of whether it was given
/// an `href`. A middle crumb with no `href` renders as plain text too, but
/// WITHOUT `aria-current` — only the last crumb is "current". Separators are
/// pure CSS (an `::before` on every non-first `<li>`), not DOM nodes. Caller
/// `Attribute...`/`.class` merge onto the `<nav>`.
///
///     Breadcrumbs([Crumb("Home", href: "/"), Crumb("Products", href: "/products"), Crumb("Widget")])
///
/// `separator:` replaces the default `/` with your own SVG glyph — pass raw
/// `<svg>` markup (e.g. a chevron-right). It renders through the `Icon` mask
/// seam: a 1em box filled with `--sw-text-muted` and clipped to the SVG's
/// shape, so it's token-colored and dark-adaptive. Same contract as `Icon`:
/// single-color by construction (the paint is the token, not the SVG's own
/// fills). Still pure CSS — the glyph rides the same `::before`, keyed off a
/// per-instance custom property, so no DOM nodes are added.
///
///     Breadcrumbs(crumbs, separator: """
///         <svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16' fill='none' \
///         stroke='currentColor' stroke-width='1.75'><path d='M6 4l4 4-4 4'/></svg>
///         """)
@MainActor
public func Breadcrumbs(_ crumbs: [Crumb], separator: String? = nil, _ attributes: Attribute...) -> VNode {
    ensureBaseStyles()
    installControlSheet(id: "sw-breadcrumbs", breadcrumbsStyleSheet)

    let items: [VNode] = crumbs.enumerated().map { index, crumb in
        let isLast = index == crumbs.count - 1
        let content: VNode
        if isLast {
            content = element("span",
                               attributes: [.attr("aria-current", "page"), .class("sw-breadcrumbs__current")],
                               children: [text(crumb.label)])
        } else if let href = crumb.href {
            content = element("a", attributes: [.class("sw-breadcrumbs__link"), .href(href)],
                               children: [text(crumb.label)])
        } else {
            content = element("span", attributes: [.class("sw-breadcrumbs__current")],
                               children: [text(crumb.label)])
        }
        return element("li", attributes: [.class("sw-breadcrumbs__item")], children: [content])
    }
    // Custom SVG separator: flag the list with the modifier class and carry the
    // encoded glyph in a per-instance custom property — the sheet's --svg-sep
    // branch masks the ::before with it (custom props inherit into pseudos).
    var olAttrs: [Attribute] = [.class(separator == nil ? "sw-breadcrumbs" : "sw-breadcrumbs sw-breadcrumbs--svg-sep")]
    if let separator {
        olAttrs.append(.style("--sw-breadcrumbs-sep", svgMaskURI(separator)))
    }
    let ol = element("ol", attributes: olAttrs, children: items)

    let navAttrs: [Attribute] = [.attr("aria-label", "Breadcrumb")] + attributes
    return element("nav", attributes: navAttrs, children: [ol])
}

let breadcrumbsStyleSheet: CSSSheet = css {
    raw("""
    .sw-breadcrumbs {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      gap: var(--sw-space-xs);
      margin: 0;
      padding: 0;
      list-style: none;
      font-size: 0.875rem;
    }
    .sw-breadcrumbs__item {
      display: flex;
      align-items: center;
      gap: var(--sw-space-xs);
    }
    .sw-breadcrumbs__item + .sw-breadcrumbs__item::before {
      content: "/";
      color: var(--sw-text-muted);
    }
    /* Custom SVG separator (the Icon mask seam): the caller's glyph arrives as a
       per-instance --sw-breadcrumbs-sep data-URI on the <ol>; the ::before swaps
       its text content for a 1em token-colored box clipped to the glyph. */
    .sw-breadcrumbs--svg-sep .sw-breadcrumbs__item + .sw-breadcrumbs__item::before {
      content: "";
      width: 1em;
      height: 1em;
      background-color: var(--sw-text-muted);
      -webkit-mask: var(--sw-breadcrumbs-sep) center / contain no-repeat;
      mask: var(--sw-breadcrumbs-sep) center / contain no-repeat;
    }
    .sw-breadcrumbs__link {
      color: var(--sw-accent);
      text-decoration: none;
      border-radius: var(--sw-radius-sm);
      transition: box-shadow var(--sw-duration) var(--sw-ease);
    }
    .sw-breadcrumbs__link:hover { text-decoration: underline; }
    .sw-breadcrumbs__link:focus-visible {
      outline: 2px solid transparent;
      box-shadow: var(--sw-focus-shadow);
    }
    .sw-breadcrumbs__current { color: var(--sw-text-muted); }
    """)
}
