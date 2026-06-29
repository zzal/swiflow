// Sources/SwiflowUI/Column.swift
import Swiflow

/// Three-way comparison result for a column's sort comparator. Defined locally so
/// SwiflowUI need not import Foundation (`ComparisonResult`) — the `.same` case is what
/// lets the table keep sorting **stable** (ties fall back to original row order).
public enum SortComparison: Equatable, Sendable { case ascending, same, descending }

/// Per-column text alignment. Logical/RTL-aware: maps to `text-align: start|center|end`
/// (matching the house logical-CSS style — see `Edge` in Tokens.swift).
public enum ColumnAlignment: Equatable, Sendable {
    case leading, center, trailing
    var cssTextAlign: String {
        switch self {
        case .leading:  return "start"
        case .center:   return "center"
        case .trailing: return "end"
        }
    }
}

/// A column width hint, written as an inline `width` on the column's cells. Use a length
/// (`.px`/`.custom`) — `fr` units are intentionally absent: they only size CSS grid tracks,
/// not table cells, so `width: Nfr` on a `<td>`/`<th>` is silently ignored by the browser.
public enum ColumnWidth: Equatable, Sendable {
    case px(Int), auto, custom(String)
    var css: String {
        switch self {
        case .px(let n):     return "\(n)px"
        case .auto:          return "auto"
        case .custom(let v): return v
        }
    }
}

/// The active sort: which column (by its stable `id`) and direction. Non-generic — the
/// table's stateful core is type-erased over `Row`, so a column id + direction is the
/// portable identity. `nil` (in the controlled binding) means unsorted.
public struct SortOrder: Equatable, Sendable {
    public var columnID: String
    public var ascending: Bool
    public init(columnID: String, ascending: Bool) {
        self.columnID = columnID
        self.ascending = ascending
    }
}

/// One column of a `DataTable`, generic over the row type. A plain value type (no macro),
/// so chained configuration is fine. Carries the header title, a stable `id`, how to render
/// a cell (`render`), an optional sort `comparator` (non-nil ⇒ sortable), and alignment/width.
public struct Column<Row> {
    /// Stable identity used by sorting + the controlled `SortOrder`. Defaults to `title`.
    public let id: String
    public let title: String
    public internal(set) var alignment: ColumnAlignment
    public internal(set) var width: ColumnWidth?
    /// Renders the cell contents for a row.
    public internal(set) var render: (Row) -> [VNode]
    /// Three-way comparator; `nil` ⇒ this column is not sortable.
    public internal(set) var comparator: ((Row, Row) -> SortComparison)?

    private init(id: String, title: String, alignment: ColumnAlignment, width: ColumnWidth?,
                 render: @escaping (Row) -> [VNode], comparator: ((Row, Row) -> SortComparison)?) {
        self.id = id; self.title = title; self.alignment = alignment; self.width = width
        self.render = render; self.comparator = comparator
    }

    /// A value column: derives BOTH a default text cell (`String(describing:)`) AND an
    /// ascending comparator from the keypath. Override rendering with `.cell { }` while
    /// keeping the comparator; drop sorting with `.sortable(false)`.
    public init<V: Comparable & CustomStringConvertible>(
        _ title: String, value keyPath: KeyPath<Row, V>, id: String? = nil
    ) {
        self.init(
            id: id ?? title, title: title, alignment: .leading, width: nil,
            render: { [text(String(describing: $0[keyPath: keyPath]))] },
            comparator: { a, b in
                let va = a[keyPath: keyPath], vb = b[keyPath: keyPath]
                if va < vb { return .ascending }
                if vb < va { return .descending }
                return .same
            }
        )
    }

    /// A custom-cell column with NO comparator (not sortable). Trailing-closure form:
    /// `Column("Actions") { row in [Button(...)] }`.
    public init(_ title: String, id: String? = nil, @ChildrenBuilder cell: @escaping (Row) -> [VNode]) {
        self.init(id: id ?? title, title: title, alignment: .leading, width: nil,
                  render: cell, comparator: nil)
    }

    /// A column sortable by a `Comparable` value that renders via a custom cell. Use this when
    /// the value is `Comparable` but not `CustomStringConvertible` (e.g. a `Comparable` enum), so
    /// the auto-text `value:` constructor doesn't apply: sorts by the keypath, renders via `cell`.
    public init<V: Comparable>(
        _ title: String, value keyPath: KeyPath<Row, V>, id: String? = nil,
        @ChildrenBuilder cell: @escaping (Row) -> [VNode]
    ) {
        self.init(
            id: id ?? title, title: title, alignment: .leading, width: nil,
            render: cell,
            comparator: { a, b in
                let va = a[keyPath: keyPath], vb = b[keyPath: keyPath]
                return va < vb ? .ascending : vb < va ? .descending : .same
            }
        )
    }

    /// Override how the cell renders (keeps the comparator, if any).
    public func cell(@ChildrenBuilder _ make: @escaping (Row) -> [VNode]) -> Column {
        var c = self; c.render = make; return c
    }

    public func align(_ alignment: ColumnAlignment) -> Column {
        var c = self; c.alignment = alignment; return c
    }

    public func width(_ width: ColumnWidth) -> Column {
        var c = self; c.width = width; return c
    }

    /// Force a value column non-sortable (clears the comparator).
    public func sortable(_ enabled: Bool) -> Column {
        var c = self; if !enabled { c.comparator = nil }; return c
    }
}

/// Collects `[Column<Row>]` from a trailing-closure block, supporting `if`/`else`/`for`
/// (mirrors `ChildrenBuilder`). Generic over `Row` so that Swift can back-propagate the
/// row type from the call-site annotation into key-path expressions inside the block.
/// Columns are a config list rebuilt each render, so plain flattening is correct —
/// no stable-slot/fragment semantics needed.
@resultBuilder
public enum ColumnBuilder<Row> {
    public static func buildExpression(_ column: Column<Row>) -> [Column<Row>] { [column] }
    public static func buildExpression(_ columns: [Column<Row>]) -> [Column<Row>] { columns }
    public static func buildBlock(_ parts: [Column<Row>]...) -> [Column<Row>] { parts.flatMap { $0 } }
    public static func buildOptional(_ part: [Column<Row>]?) -> [Column<Row>] { part ?? [] }
    public static func buildEither(first: [Column<Row>]) -> [Column<Row>] { first }
    public static func buildEither(second: [Column<Row>]) -> [Column<Row>] { second }
    public static func buildArray(_ parts: [[Column<Row>]]) -> [Column<Row>] { parts.flatMap { $0 } }
}
