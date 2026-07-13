// Tests/SwiflowUITests/BreadcrumbsTests.swift
import Testing
import Swiflow
@testable import SwiflowUI

@MainActor
private func elementOf(_ node: VNode) -> ElementData? {
    guard case .element(let data) = node else { return nil }
    return data
}

@Suite("Breadcrumbs")
@MainActor
struct BreadcrumbsTests {
    @Test("renders <nav aria-label=\"Breadcrumb\"> wrapping an <ol class=\"sw-breadcrumbs\">")
    func rendersNavAndOl() {
        let nav = elementOf(Breadcrumbs([Crumb("Home", href: "/"), Crumb("Settings")]))!
        #expect(nav.tag == "nav")
        #expect(nav.attributes["aria-label"] == "Breadcrumb")
        #expect(nav.children.count == 1)
        let ol = elementOf(nav.children[0])!
        #expect(ol.tag == "ol")
        #expect(ol.attributes["class"] == "sw-breadcrumbs")
    }

    @Test("one <li> per crumb") func onePerCrumb() {
        let nav = elementOf(Breadcrumbs([
            Crumb("Home", href: "/"), Crumb("Library", href: "/library"), Crumb("Settings"),
        ]))!
        let ol = elementOf(nav.children[0])!
        #expect(ol.children.count == 3)
        for li in ol.children {
            #expect(elementOf(li)?.tag == "li")
            #expect(elementOf(li)?.attributes["class"] == "sw-breadcrumbs__item")
        }
    }

    @Test("a crumb with an href renders a sanitized <a>") func middleCrumbWithHrefRendersAnchor() {
        let nav = elementOf(Breadcrumbs([
            Crumb("Home", href: "/"), Crumb("Library", href: "/library"), Crumb("Settings"),
        ]))!
        let ol = elementOf(nav.children[0])!
        let firstLi = elementOf(ol.children[0])!
        let a = elementOf(firstLi.children[0])!
        #expect(a.tag == "a")
        #expect(a.attributes["href"] == "/")
        if case .text(let t) = a.children[0] { #expect(t == "Home") } else { Issue.record("no text child") }
    }

    @Test("a javascript: href on a crumb is scrubbed by URLSanitizer") func sanitizesJavascriptHref() {
        let raw = "javascript:alert(1)"
        let nav = elementOf(Breadcrumbs([Crumb("Danger", href: raw), Crumb("Current")]))!
        let ol = elementOf(nav.children[0])!
        let firstLi = elementOf(ol.children[0])!
        let a = elementOf(firstLi.children[0])!
        #expect(a.attributes["href"] != raw)
    }

    @Test("the last crumb renders as plain text with aria-current=page, never a link — even with an href")
    func lastCrumbIsCurrentNotLink() {
        let nav = elementOf(Breadcrumbs([Crumb("Home", href: "/"), Crumb("Settings", href: "/settings")]))!
        let ol = elementOf(nav.children[0])!
        let lastLi = elementOf(ol.children[1])!
        let current = elementOf(lastLi.children[0])!
        #expect(current.tag == "span")
        #expect(current.attributes["aria-current"] == "page")
        #expect(current.attributes["class"] == "sw-breadcrumbs__current")
        if case .text(let t) = current.children[0] { #expect(t == "Settings") } else { Issue.record("no text child") }
    }

    @Test("a middle crumb without an href renders plain text WITHOUT aria-current")
    func middleCrumbWithoutHrefIsPlainTextNoCurrent() {
        let nav = elementOf(Breadcrumbs([
            Crumb("Home", href: "/"), Crumb("Archived"), Crumb("Settings", href: "/settings"),
        ]))!
        let ol = elementOf(nav.children[0])!
        let middleLi = elementOf(ol.children[1])!
        let middle = elementOf(middleLi.children[0])!
        #expect(middle.tag == "span")
        #expect(middle.attributes["aria-current"] == nil)
        if case .text(let t) = middle.children[0] { #expect(t == "Archived") } else { Issue.record("no text child") }
    }

    @Test("caller attributes merge onto the <nav>") func callerAttributesMergeOntoNav() {
        let nav = elementOf(Breadcrumbs([Crumb("Home", href: "/"), Crumb("Settings")],
                                         .attr("data-testid", "crumbs")))!
        #expect(nav.attributes["data-testid"] == "crumbs")
        #expect(nav.attributes["aria-label"] == "Breadcrumb")
    }

    @Test("an empty crumb list renders an empty <ol> without crashing") func emptyCrumbsRendersEmptyOl() {
        let nav = elementOf(Breadcrumbs([]))!
        let ol = elementOf(nav.children[0])!
        #expect(ol.tag == "ol")
        #expect(ol.children.isEmpty)
    }
}
