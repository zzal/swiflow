// Tests/SwiflowUITests/ColumnTests.swift
import Testing
@testable import Swiflow
@testable import SwiflowUI

private struct Person: Identifiable { let id: Int; let name: String; let age: Int }

@MainActor private func textOf(_ nodes: [VNode]) -> String {
    nodes.map { node -> String in
        switch node {
        case .text(let s): return s
        case .element(let d): return d.children.map { textOf([$0]) }.joined()
        default: return ""
        }
    }.joined()
}

@Suite("Column model")
@MainActor
struct ColumnTests {
    private let ada = Person(id: 1, name: "Ada", age: 36)
    private let bob = Person(id: 2, name: "Bob", age: 28)

    @Test("value column derives a text cell from the keypath") func valueCell() {
        let col = Column<Person>("Name", value: \.name)
        #expect(textOf(col.render(ada)) == "Ada")
    }

    @Test("value column derives a comparator (ascending by value)") func valueComparator() {
        let col = Column<Person>("Age", value: \.age)
        #expect(col.comparator != nil)
        #expect(col.comparator!(bob, ada) == .ascending)   // 28 < 36
        #expect(col.comparator!(ada, bob) == .descending)
        #expect(col.comparator!(ada, ada) == .same)
    }

    @Test(".cell overrides rendering but keeps the comparator") func cellOverride() {
        let col = Column<Person>("Age", value: \.age).cell { p in [text("#\(p.age)")] }
        #expect(textOf(col.render(ada)) == "#36")
        #expect(col.comparator != nil)   // still sortable by .age
    }

    @Test("custom-cell column has no comparator (not sortable)") func customNotSortable() {
        let col = Column<Person>("Actions") { _ in [text("edit")] }
        #expect(col.comparator == nil)
    }

    @Test(".sortable(false) drops the comparator") func optOut() {
        let col = Column<Person>("Age", value: \.age).sortable(false)
        #expect(col.comparator == nil)
    }

    @Test("alignment and width modifiers set the fields") func alignWidth() {
        let col = Column<Person>("Age", value: \.age).align(.trailing).width(.px(80))
        #expect(col.alignment == .trailing)
        #expect(col.width == .px(80))
    }

    @Test("default id is the title; explicit id wins") func ids() {
        #expect(Column<Person>("Age", value: \.age).id == "Age")
        #expect(Column<Person>("Age", value: \.age, id: "age-col").id == "age-col")
    }

    @Test("ColumnBuilder collects columns including if/for") func builder() {
        let show = true
        let cols: [Column<Person>] = buildColumns {
            Column("Name", value: \.name)
            if show { Column("Age", value: \.age) }
            for label in ["X", "Y"] { Column(label) { _ in [text(label)] } }
        }
        #expect(cols.map(\.title) == ["Name", "Age", "X", "Y"])
    }

    @Test("ColumnWidth/Alignment css") func css() {
        #expect(ColumnAlignment.leading.cssTextAlign == "start")
        #expect(ColumnAlignment.center.cssTextAlign == "center")
        #expect(ColumnAlignment.trailing.cssTextAlign == "end")
        #expect(ColumnWidth.px(80).css == "80px")
        #expect(ColumnWidth.auto.css == "auto")
        #expect(ColumnWidth.custom("10ch").css == "10ch")
    }
}

// Local helper to exercise @ColumnBuilder (the real one is consumed by DataTable factories).
// Note: @ColumnBuilder<Row> is required (not @ColumnBuilder) because ColumnBuilder is generic
// over Row; the type parameter lets Swift infer the key-path root type in the builder closure.
@MainActor private func buildColumns<Row>(@ColumnBuilder<Row> _ make: () -> [Column<Row>]) -> [Column<Row>] { make() }
