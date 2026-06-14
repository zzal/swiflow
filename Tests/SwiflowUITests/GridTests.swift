// Tests/SwiflowUITests/GridTests.swift
import Testing
import Swiflow
@testable import SwiflowUI

@MainActor
private func styleOf(_ node: VNode) -> [String: String] {
    guard case .element(let data) = node else { return [:] }
    return data.style
}

@Suite("Grid")
@MainActor
struct GridTests {
    @Test("Grid lowers to display:grid with template columns and a token gap") func gridLowersToGrid() {
        let s = styleOf(Grid(columns: 3, spacing: .md) { text("x") })
        #expect(s["display"] == "grid")
        #expect(s["grid-template-columns"] == "repeat(3, minmax(0, 1fr))")
        #expect(s["gap"] == "var(--sw-space-md)")
    }

    @Test("columns: count uses a safe minmax(0, 1fr) repeat") func countMapsToSafeRepeat() {
        #expect(GridColumns.count(4).css == "repeat(4, minmax(0, 1fr))")
    }

    @Test("columns: template passes its raw track list through") func templatePassesThrough() {
        #expect(GridColumns.template("1fr 2fr").css == "1fr 2fr")
        #expect(styleOf(Grid(columns: .template("1fr auto")) { text("x") })["grid-template-columns"] == "1fr auto")
    }

    @Test("integer literal builds .count; string literal builds .template") func literalsBuildCases() {
        #expect((3 as GridColumns) == .count(3))
        #expect(("1fr 2fr" as GridColumns) == .template("1fr 2fr"))
    }

    @Test("Default .none spacing emits no gap property") func gapOmittedWhenNone() {
        #expect(styleOf(Grid(columns: 2) { text("x") })["gap"] == nil)
    }

    @Test("Caller-supplied style wins over the grid defaults") func callerStyleWins() {
        #expect(styleOf(Grid(columns: 2, .style("display", "flex")) { text("x") })["display"] == "flex")
    }

    @Test("Grid renders as a div keeping its children intact") func preservesChildren() {
        let node = Grid(columns: 2) { text("a"); text("b") }
        guard case .element(let data) = node else { Issue.record("not element"); return }
        #expect(data.tag == "div")
        #expect(data.children.count == 2)
    }
}
