// Tests/SwiflowUITests/DataTableTests.swift
// DataTable is a STATEFUL @Component (DataTableBox) behind a generic factory that erases
// rows/columns into index closures. Host tests render `makeDataTableBox(...).body` inside
// `building { }` (handler-ambient) and inspect the VNode tree. The internal-@State default
// sort/page path is exercised via controlled bindings here and end-to-end in the demo e2e.
import Testing
@testable import Swiflow
@testable import SwiflowUI

private struct Person: Identifiable, Equatable { let id: Int; let name: String; let age: Int }

@MainActor private func el(_ node: VNode?) -> ElementData? {
    if case .element(let d)? = node { return d }
    return nil
}
@MainActor private func allText(_ node: VNode) -> String {
    switch node {
    case .text(let s): return s
    case .element(let d): return d.children.map(allText).joined()
    case .fragment(let xs): return xs.map(allText).joined()
    case .environmentOverride(_, let c): return allText(c)
    default: return ""
    }
}
/// Depth-first collect every element with the given tag.
@MainActor private func allTags(_ node: VNode, _ tag: String) -> [ElementData] {
    var out: [ElementData] = []
    func walk(_ n: VNode) {
        if case .element(let d) = n {
            if d.tag == tag { out.append(d) }
            for c in d.children { walk(c) }
        } else if case .fragment(let xs) = n { xs.forEach(walk) }
    }
    walk(node); return out
}
@MainActor private func building<T>(_ body: () -> T) -> T {
    let prev = HandlerAmbient.current
    HandlerAmbient.current = HandlerRegistry()
    defer { HandlerAmbient.current = prev }
    return body()
}

private let people = [Person(id: 1, name: "Ada", age: 36),
                      Person(id: 2, name: "Bob", age: 28),
                      Person(id: 3, name: "Cy",  age: 41)]

@Suite("DataTable — base render")
@MainActor
struct DataTableBaseTests {
    private func box(_ rows: [Person] = people) -> DataTableBox {
        makeDataTableBox(rows, id: \.id) {
            Column("Name", value: \.name)
            Column("Age", value: \.age).align(.trailing).width(.px(80))
        }
    }

    @Test("renders table > thead/tbody with a header row of <th scope=col>") func structure() {
        let root = building { box().body }
        let table = allTags(root, "table").first!
        #expect(table.attributes["class"]?.contains("sw-table") == true)
        let ths = allTags(root, "th")
        #expect(ths.map { allText(.element($0)) } == ["Name", "Age"])
        #expect(ths.allSatisfy { $0.attributes["scope"] == "col" })
    }

    @Test("a <tr> per row, keyed by id, with default text cells") func rows() {
        let root = building { box().body }
        let bodyRows = allTags(root, "tbody").first.map { allTags(.element($0), "tr") } ?? []
        #expect(bodyRows.count == 3)
        #expect(bodyRows.map(\.key) == ["1", "2", "3"])           // keyed by id for diff reuse
        let firstCells = allTags(.element(bodyRows[0]), "td")
        #expect(firstCells.map { allText(.element($0)) } == ["Ada", "36"])
    }

    @Test("custom .cell overrides rendering") func customCell() {
        let b = makeDataTableBox(people, id: \.id) {
            Column("Age", value: \.age).cell { p in [text("#\(p.age)")] }
        }
        let root = building { b.body }
        let firstTd = allTags(.element(allTags(root, "tbody").first!), "td").first!
        #expect(allText(.element(firstTd)) == "#36")
    }

    @Test("alignment + width emit inline styles on header and cells") func alignWidth() {
        let root = building { box().body }
        let ageTh = allTags(root, "th").first { allText(.element($0)) == "Age" }!
        #expect(ageTh.style["text-align"] == "end")
        #expect(ageTh.style["width"] == "80px")
        let ageTd = allTags(.element(allTags(root, "tbody").first!), "td")[1]
        #expect(ageTd.style["text-align"] == "end")
        #expect(ageTd.style["width"] == "80px")
    }

    @Test("table sits inside a scroll container; maxHeight sets max-height") func scrollContainer() {
        let b = makeDataTableBox(people, id: \.id, maxHeight: .custom("480px")) { Column("Name", value: \.name) }
        let root = building { b.body }
        let scroll = allTags(root, "div").first { $0.attributes["class"]?.contains("sw-table__scroll") == true }!
        #expect(scroll.style["max-height"] == "480px")
    }
}
