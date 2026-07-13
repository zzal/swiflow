// Sources/SwiflowUI/TextLink.swift
import Swiflow

/// A styled inline text hyperlink — a token-skinned `<a>`. Named `TextLink`, not
/// `Link`: `SwiflowRouter.Link` is the in-app (SPA) navigation link; this is a plain
/// hyperlink for external or non-routed destinations. The `href` is sanitized
/// automatically (the `.href` DSL modifier folds it through `URLSanitizer`), so a
/// `javascript:`/`data:` URL is neutralized. `external: true` opens in a new tab with
/// `rel="noopener noreferrer"`. Caller `Attribute...`/`.class` merge onto the `<a>`.
///
///     TextLink("Docs", href: "https://example.com/docs")
///     TextLink("Report", href: "https://example.com", external: true)
@MainActor
public func TextLink(_ label: String, href: String, external: Bool = false,
                     _ attributes: Attribute...) -> VNode {
    textLinkNode(href: href, external: external, attributes: attributes, children: [text(label)])
}

@MainActor
public func TextLink(href: String, external: Bool = false, _ attributes: Attribute...,
                     @ChildrenBuilder content: () -> [VNode]) -> VNode {
    textLinkNode(href: href, external: external, attributes: attributes, children: content())
}

@MainActor
private func textLinkNode(href: String, external: Bool, attributes: [Attribute],
                          children: [VNode]) -> VNode {
    ensureBaseStyles()
    installControlSheet(id: "sw-link", textLinkStyleSheet)
    let (callerClasses, callerRest) = splitClasses(attributes)
    let cls = (["sw-link"] + callerClasses).joined(separator: " ")
    var attrs: [Attribute] = [.class(cls), .href(href)]
    if external {
        attrs.append(.attr("target", "_blank"))
        attrs.append(.attr("rel", "noopener noreferrer"))
    }
    attrs += callerRest
    return element("a", attributes: attrs, children: children)
}

let textLinkStyleSheet: CSSSheet = css {
    raw("""
    .sw-link {
      color: var(--sw-accent);
      text-decoration: underline;
      text-underline-offset: 0.15em;
      text-decoration-thickness: from-font;
      border-radius: var(--sw-radius-sm);
      transition: color var(--sw-duration) var(--sw-ease);
    }
    .sw-link:hover { color: var(--sw-accent-hover); }
    .sw-link:focus-visible {
      outline: var(--sw-focus-ring-width) solid var(--sw-focus-ring);
      outline-offset: 2px;
    }
    """)
}
