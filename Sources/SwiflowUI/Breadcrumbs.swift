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
@MainActor
public func Breadcrumbs(_ crumbs: [Crumb], _ attributes: Attribute...) -> VNode {
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
    let ol = element("ol", attributes: [.class("sw-breadcrumbs")], children: items)

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
    .sw-breadcrumbs__link {
      color: var(--sw-accent);
      text-decoration: none;
    }
    .sw-breadcrumbs__link:hover { text-decoration: underline; }
    .sw-breadcrumbs__link:focus-visible {
      outline: var(--sw-focus-ring-width) solid var(--sw-focus-ring);
      outline-offset: 2px;
    }
    .sw-breadcrumbs__current { color: var(--sw-text-muted); }
    """)
}
