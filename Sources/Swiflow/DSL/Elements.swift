// Sources/Swiflow/DSL/Elements.swift
//
// The 20 lowercase factories below are deliberately mechanical: each takes
// variadic `Attribute...` plus an optional `@ChildrenBuilder` block, and
// (for content-bearing tags) ships a text-only convenience overload. The
// repetition is the API — a generic `element(_:_:children:)` was tried and
// removed because variadic forwarding in Swift makes the wrappers no shorter
// and obscures call-site discoverability. A macro could regenerate this file
// from a tag list; deferred to Phase 4 polish.

// MARK: - Concrete elements

public func div(
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    .element(applyAttributes(tag: "div", attributes, children: children()))
}

public func span(
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    .element(applyAttributes(tag: "span", attributes, children: children()))
}

public func p(
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    .element(applyAttributes(tag: "p", attributes, children: children()))
}

public func p(_ text: String, _ attributes: Attribute...) -> VNode {
    .element(applyAttributes(tag: "p", attributes, children: [.text(text)]))
}

public func h1(
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    .element(applyAttributes(tag: "h1", attributes, children: children()))
}

public func h1(_ text: String, _ attributes: Attribute...) -> VNode {
    .element(applyAttributes(tag: "h1", attributes, children: [.text(text)]))
}

public func h2(
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    .element(applyAttributes(tag: "h2", attributes, children: children()))
}

public func h2(_ text: String, _ attributes: Attribute...) -> VNode {
    .element(applyAttributes(tag: "h2", attributes, children: [.text(text)]))
}

public func h3(
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    .element(applyAttributes(tag: "h3", attributes, children: children()))
}

public func h3(_ text: String, _ attributes: Attribute...) -> VNode {
    .element(applyAttributes(tag: "h3", attributes, children: [.text(text)]))
}

public func button(
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    .element(applyAttributes(tag: "button", attributes, children: children()))
}

public func button(_ text: String, _ attributes: Attribute...) -> VNode {
    .element(applyAttributes(tag: "button", attributes, children: [.text(text)]))
}

public func a(
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    .element(applyAttributes(tag: "a", attributes, children: children()))
}

public func a(_ text: String, _ attributes: Attribute...) -> VNode {
    .element(applyAttributes(tag: "a", attributes, children: [.text(text)]))
}

public func input(_ attributes: Attribute...) -> VNode {
    .element(applyAttributes(tag: "input", attributes))
}

public func img(_ attributes: Attribute...) -> VNode {
    .element(applyAttributes(tag: "img", attributes))
}

public func ul(
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    .element(applyAttributes(tag: "ul", attributes, children: children()))
}

public func li(
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    .element(applyAttributes(tag: "li", attributes, children: children()))
}

public func li(_ text: String, _ attributes: Attribute...) -> VNode {
    .element(applyAttributes(tag: "li", attributes, children: [.text(text)]))
}

public func form(
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    .element(applyAttributes(tag: "form", attributes, children: children()))
}

public func label(
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    .element(applyAttributes(tag: "label", attributes, children: children()))
}

public func label(_ text: String, _ attributes: Attribute...) -> VNode {
    .element(applyAttributes(tag: "label", attributes, children: [.text(text)]))
}

public func pre(
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    .element(applyAttributes(tag: "pre", attributes, children: children()))
}

public func code(
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    .element(applyAttributes(tag: "code", attributes, children: children()))
}

public func code(_ text: String, _ attributes: Attribute...) -> VNode {
    .element(applyAttributes(tag: "code", attributes, children: [.text(text)]))
}

public func section(
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    .element(applyAttributes(tag: "section", attributes, children: children()))
}

public func header(
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    .element(applyAttributes(tag: "header", attributes, children: children()))
}

public func footer(
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    .element(applyAttributes(tag: "footer", attributes, children: children()))
}

public func nav(
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    .element(applyAttributes(tag: "nav", attributes, children: children()))
}

/// `main` is a Swift keyword in some attribute contexts; spell the factory
/// `main_` to avoid surprising users.
public func main_(
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    .element(applyAttributes(tag: "main", attributes, children: children()))
}
