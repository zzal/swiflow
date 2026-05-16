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

/// HTML `<div>` — generic block container.
public func div(
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    .element(applyAttributes(tag: "div", attributes, children: children()))
}

/// HTML `<span>` — generic inline container.
public func span(
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    .element(applyAttributes(tag: "span", attributes, children: children()))
}

/// HTML `<p>` paragraph with attributes and a children block.
public func p(
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    .element(applyAttributes(tag: "p", attributes, children: children()))
}

/// Text-only convenience for `<p>`: a single text node child.
public func p(_ text: String, _ attributes: Attribute...) -> VNode {
    .element(applyAttributes(tag: "p", attributes, children: [.text(text)]))
}

/// HTML `<h1>` heading with attributes and a children block.
public func h1(
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    .element(applyAttributes(tag: "h1", attributes, children: children()))
}

/// Text-only convenience for `<h1>`: a single text node child.
public func h1(_ text: String, _ attributes: Attribute...) -> VNode {
    .element(applyAttributes(tag: "h1", attributes, children: [.text(text)]))
}

/// HTML `<h2>` heading with attributes and a children block.
public func h2(
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    .element(applyAttributes(tag: "h2", attributes, children: children()))
}

/// Text-only convenience for `<h2>`: a single text node child.
public func h2(_ text: String, _ attributes: Attribute...) -> VNode {
    .element(applyAttributes(tag: "h2", attributes, children: [.text(text)]))
}

/// HTML `<h3>` heading with attributes and a children block.
public func h3(
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    .element(applyAttributes(tag: "h3", attributes, children: children()))
}

/// Text-only convenience for `<h3>`: a single text node child.
public func h3(_ text: String, _ attributes: Attribute...) -> VNode {
    .element(applyAttributes(tag: "h3", attributes, children: [.text(text)]))
}

/// HTML `<button>` with attributes and a children block. Attach a click
/// handler via `.on("click", registry.register { … })`.
public func button(
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    .element(applyAttributes(tag: "button", attributes, children: children()))
}

/// Text-only convenience for `<button>`: a single text label.
public func button(_ text: String, _ attributes: Attribute...) -> VNode {
    .element(applyAttributes(tag: "button", attributes, children: [.text(text)]))
}

/// HTML `<a>` anchor with attributes and a children block. Use
/// `.attr("href", "…")` to set the target.
public func a(
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    .element(applyAttributes(tag: "a", attributes, children: children()))
}

/// Text-only convenience for `<a>`: a single text node child.
public func a(_ text: String, _ attributes: Attribute...) -> VNode {
    .element(applyAttributes(tag: "a", attributes, children: [.text(text)]))
}

/// HTML `<input>` — a void element. No children block: HTML inputs cannot
/// contain content.
public func input(_ attributes: Attribute...) -> VNode {
    .element(applyAttributes(tag: "input", attributes))
}

/// HTML `<img>` — a void element. No children block: images cannot contain
/// content.
public func img(_ attributes: Attribute...) -> VNode {
    .element(applyAttributes(tag: "img", attributes))
}

/// HTML `<ul>` unordered list with attributes and a children block (typically
/// `<li>` factories).
public func ul(
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    .element(applyAttributes(tag: "ul", attributes, children: children()))
}

/// HTML `<li>` list item with attributes and a children block. Pair with
/// `.key(_:)` inside `for` loops to enable the keyed diff strategy.
public func li(
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    .element(applyAttributes(tag: "li", attributes, children: children()))
}

/// Text-only convenience for `<li>`: a single text node child.
public func li(_ text: String, _ attributes: Attribute...) -> VNode {
    .element(applyAttributes(tag: "li", attributes, children: [.text(text)]))
}

/// HTML `<form>` with attributes and a children block. Attach a submit
/// handler via `.on("submit", …)`.
public func form(
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    .element(applyAttributes(tag: "form", attributes, children: children()))
}

/// HTML `<label>` with attributes and a children block.
public func label(
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    .element(applyAttributes(tag: "label", attributes, children: children()))
}

/// Text-only convenience for `<label>`: a single text node child.
public func label(_ text: String, _ attributes: Attribute...) -> VNode {
    .element(applyAttributes(tag: "label", attributes, children: [.text(text)]))
}

/// HTML `<pre>` preformatted block with attributes and a children block.
public func pre(
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    .element(applyAttributes(tag: "pre", attributes, children: children()))
}

/// HTML `<code>` inline code with attributes and a children block.
public func code(
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    .element(applyAttributes(tag: "code", attributes, children: children()))
}

/// Text-only convenience for `<code>`: a single text node child.
public func code(_ text: String, _ attributes: Attribute...) -> VNode {
    .element(applyAttributes(tag: "code", attributes, children: [.text(text)]))
}

/// HTML `<section>` landmark with attributes and a children block.
public func section(
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    .element(applyAttributes(tag: "section", attributes, children: children()))
}

/// HTML `<header>` landmark with attributes and a children block.
public func header(
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    .element(applyAttributes(tag: "header", attributes, children: children()))
}

/// HTML `<footer>` landmark with attributes and a children block.
public func footer(
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    .element(applyAttributes(tag: "footer", attributes, children: children()))
}

/// HTML `<nav>` landmark with attributes and a children block.
public func nav(
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    .element(applyAttributes(tag: "nav", attributes, children: children()))
}

/// HTML `<main>` landmark with attributes and a children block.
///
/// `main` is a Swift keyword in some attribute contexts; spell the factory
/// `main_` to avoid surprising users.
public func main_(
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    .element(applyAttributes(tag: "main", attributes, children: children()))
}
