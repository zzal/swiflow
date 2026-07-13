// Tests/SwiflowUITests/PaginationTests.swift
// Pagination is a faithful lift of DataTable's inline pager (see DataTable.swift's old
// `pager(page:)`/`navBtn`) into a standalone, general control: `.sw-pagination` div,
// Previous/Next `.sw-pagination__btn` buttons (aria-labeled, `inert` — not `disabled`,
// project rule — at the ends, and with NO click handler while inert), and a
// `.sw-pagination__info` "Page X of N" span (1-based display over a 0-based page index).
// These host tests mirror ToggleButtonGroupTests/TabsTests: structure + inert state, then
// click dispatched through HandlerRegistry (the `building { }` seam).
import Testing
@testable import Swiflow      // HandlerAmbient / HandlerRegistry / EventInfo for the click dispatch
@testable import SwiflowUI

@MainActor private func el(_ node: VNode?) -> ElementData? {
    if case .element(let data)? = node { return data }
    return nil
}

@MainActor private func buttons(_ root: ElementData) -> [ElementData] {
    root.children.compactMap { el($0) }.filter { $0.tag == "button" }
}

@MainActor private func info(_ root: ElementData) -> ElementData? {
    root.children.compactMap { el($0) }.first { $0.tag == "span" }
}

@MainActor private func building<T>(_ body: () -> T) -> T {
    let prev = HandlerAmbient.current
    HandlerAmbient.current = HandlerRegistry()
    defer { HandlerAmbient.current = prev }
    return body()
}

@Suite("Pagination")
@MainActor
struct PaginationTests {
    @Test("renders a .sw-pagination div: Previous button, page info span, Next button") func structure() {
        let root = el(building { Pagination(currentPage: 1, pageCount: 5, onChange: { _ in }) })!
        #expect(root.tag == "div")
        #expect(root.attributes["class"] == "sw-pagination")

        let btns = buttons(root)
        #expect(btns.count == 2)
        #expect(btns.allSatisfy { $0.attributes["type"] == "button" })
        #expect(btns.allSatisfy { $0.attributes["class"] == "sw-pagination__btn" })
        #expect(btns[0].attributes["aria-label"] == "Previous")
        #expect(btns[1].attributes["aria-label"] == "Next")

        let infoSpan = info(root)!
        #expect(infoSpan.attributes["class"] == "sw-pagination__info")
    }

    @Test("page info is 1-based: \"Page X of N\" over the 0-based currentPage") func pageInfoText() {
        let root = el(building { Pagination(currentPage: 2, pageCount: 5, onChange: { _ in }) })!
        let infoSpan = info(root)!
        #expect(infoSpan.children.count == 1)
        if case .text(let s)? = infoSpan.children.first {
            #expect(s == "Page 3 of 5")
        } else {
            Issue.record("expected a text child")
        }
    }

    @Test("Previous is inert on the first page (currentPage <= 0) and has NO click handler") func previousInertAtStart() {
        let root = el(building { Pagination(currentPage: 0, pageCount: 5, onChange: { _ in }) })!
        let btns = buttons(root)
        #expect(btns[0].attributes["inert"] == "")
        #expect(btns[0].handlers["click"] == nil)
    }

    @Test("Previous is NOT inert past the first page, and has a click handler") func previousActiveMidway() {
        let root = el(building { Pagination(currentPage: 1, pageCount: 5, onChange: { _ in }) })!
        let btns = buttons(root)
        #expect(btns[0].attributes["inert"] == nil)
        #expect(btns[0].handlers["click"] != nil)
    }

    @Test("Next is inert on the last page (currentPage >= pageCount - 1) and has NO click handler") func nextInertAtEnd() {
        let root = el(building { Pagination(currentPage: 4, pageCount: 5, onChange: { _ in }) })!
        let btns = buttons(root)
        #expect(btns[1].attributes["inert"] == "")
        #expect(btns[1].handlers["click"] == nil)
    }

    @Test("Next is NOT inert before the last page, and has a click handler") func nextActiveMidway() {
        let root = el(building { Pagination(currentPage: 1, pageCount: 5, onChange: { _ in }) })!
        let btns = buttons(root)
        #expect(btns[1].attributes["inert"] == nil)
        #expect(btns[1].handlers["click"] != nil)
    }

    @Test("clicking Previous dispatches through HandlerRegistry with currentPage - 1") func clickPrevious() {
        let registry = HandlerRegistry()
        HandlerAmbient.current = registry
        defer { HandlerAmbient.current = nil }
        var received: Int?
        let btns = buttons(el(Pagination(currentPage: 2, pageCount: 5, onChange: { received = $0 }))!)
        registry.dispatch(id: btns[0].handlers["click"]!.id, event: EventInfo(type: "click"))
        #expect(received == 1)
    }

    @Test("clicking Next dispatches through HandlerRegistry with currentPage + 1") func clickNext() {
        let registry = HandlerRegistry()
        HandlerAmbient.current = registry
        defer { HandlerAmbient.current = nil }
        var received: Int?
        let btns = buttons(el(Pagination(currentPage: 2, pageCount: 5, onChange: { received = $0 }))!)
        registry.dispatch(id: btns[1].handlers["click"]!.id, event: EventInfo(type: "click"))
        #expect(received == 3)
    }

    // MARK: - Binding overload

    @Test("Binding overload: clicking Next writes the bound page") func bindingOverloadWritesPage() {
        let registry = HandlerRegistry()
        HandlerAmbient.current = registry
        defer { HandlerAmbient.current = nil }
        var p = 2
        let page = Binding<Int>(get: { p }, set: { p = $0 })
        let btns = buttons(el(Pagination(page: page, pageCount: 5))!)
        registry.dispatch(id: btns[1].handlers["click"]!.id, event: EventInfo(type: "click"))
        #expect(p == 3)
    }

    @Test("Binding overload: same structure/inert rules as the core overload") func bindingOverloadStructure() {
        let page = Binding<Int>(get: { 0 }, set: { _ in })
        let root = el(building { Pagination(page: page, pageCount: 5) })!
        #expect(root.attributes["class"] == "sw-pagination")
        let btns = buttons(root)
        #expect(btns[0].attributes["inert"] == "")
        #expect(btns[1].attributes["inert"] == nil)
    }

    // MARK: - Caller attrs

    @Test("caller attrs/.class merge onto the root div") func callerAttrsMerge() {
        let root = el(building {
            Pagination(currentPage: 0, pageCount: 5, onChange: { _ in }, .class("mine"), .data("test", "pg"))
        })!
        #expect(root.attributes["class"] == "sw-pagination mine")
        #expect(root.attributes["data-test"] == "pg")
    }

    @Test("stylesheet: pagination chrome, inert-aware, token-driven") func stylesheet() {
        let css = paginationSheet.cssString(scopeClass: "")
        #expect(css.contains(".sw-pagination"))
        #expect(css.contains(".sw-pagination__info"))
        #expect(css.contains(".sw-pagination__btn"))
        #expect(css.contains("[inert]"))
        #expect(css.filter { $0 == "{" }.count == css.filter { $0 == "}" }.count)
    }
}
