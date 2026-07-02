// Sources/App/NavBar.swift
import Swiflow
import SwiflowDOM
import SwiflowRouter
import SwiflowUI

/// Tab bar shared by both pages. `Link` renders a fixed-shape `<a>`, so the
/// styling targets `nav a` from the scoped sheet rather than per-link classes.
final class NavBar: Component {
    @MainActor static var scopedStyles: CSSSheet? = css {
        // `host(...)` — the <nav> is the component root, and scoped `rule(...)`
        // selectors only reach descendants.
        host(.display("flex"),
             .alignItems("center"),
             .gap("var(--sw-space-sm)"),
             .padding("var(--sw-space-sm) var(--sw-space-md)"),
             .borderBottom("1px solid color-mix(in srgb, var(--sw-text) 15%, transparent)"))
        rule("a",
             .color("var(--sw-text)"),
             .textDecoration("none"),
             .padding("var(--sw-space-xs) var(--sw-space-md)"),
             .borderRadius("var(--sw-radius)"))
        rule("a:hover",
             .background("color-mix(in srgb, var(--sw-accent) 15%, transparent)"))
        rule(".brand",
             .fontWeight("700"),
             .marginRight("var(--sw-space-md)"))
    }

    var body: VNode {
        nav {
            span(.class("brand")) { text("🌍 Mission Control") }
            embed { Link("/", "Weather") }
            embed { Link("/quakes", "Quakes") }
        }
    }
}
