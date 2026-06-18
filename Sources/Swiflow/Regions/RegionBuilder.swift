// Sources/Swiflow/Regions/RegionBuilder.swift

public extension ChildrenBuilder {
    /// Lift a typed region into the children list.
    static func buildExpression<G: RegionGuest>(_ expression: RegionView<G>) -> [VNode] {
        [expression.asVNode()]
    }
}
