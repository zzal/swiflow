public extension CSSSheet {
    static func + (lhs: CSSSheet, rhs: CSSSheet) -> CSSSheet {
        CSSSheet(entries: lhs.entries + rhs.entries)
    }
}
