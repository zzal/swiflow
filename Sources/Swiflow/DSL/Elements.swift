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
/// handler via `.on(.click) { … }`.
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
/// `.attr("href", "…")` to set the target. Named `link` to avoid the
/// one-letter free function `a` in the public namespace.
public func link(
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    .element(applyAttributes(tag: "a", attributes, children: children()))
}

/// Text-only convenience for `<a>`: a single text node child. Named `link`
/// to avoid the one-letter free function `a` in the public namespace.
public func link(_ text: String, _ attributes: Attribute...) -> VNode {
    .element(applyAttributes(tag: "a", attributes, children: [.text(text)]))
}

/// HTML `<input>` — a void element. No children block: HTML inputs cannot
/// contain content.
public func input(_ attributes: Attribute...) -> VNode {
    .element(applyAttributes(tag: "input", attributes))
}

/// HTML `<textarea>` — text content goes between the tags. Pass an empty
/// string to leave the textarea uncontrolled by initial content; pair
/// with `.value($binding)` for two-way binding (Phase 7).
public func textarea(_ text: String = "", _ attributes: Attribute...) -> VNode {
    let children: [VNode] = text.isEmpty ? [] : [.text(text)]
    return .element(applyAttributes(tag: "textarea", attributes, children: children))
}

/// HTML `<textarea>` with block-form children — rare; the string overload
/// above covers almost every use.
public func textarea(
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode]
) -> VNode {
    .element(applyAttributes(tag: "textarea", attributes, children: children()))
}

/// HTML `<select>` — children are `option(...)` nodes. Pair with
/// `.selection($binding)` for two-way binding (Phase 7).
public func select(
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    .element(applyAttributes(tag: "select", attributes, children: children()))
}

/// HTML `<option>` — text label as content; `.attr("value", ...)` sets the
/// underlying form value selected when this option is chosen.
public func option(_ label: String, _ attributes: Attribute...) -> VNode {
    let children: [VNode] = label.isEmpty ? [] : [.text(label)]
    return .element(applyAttributes(tag: "option", attributes, children: children))
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
/// handler via `.on(.submit) { … }`.
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
/// Named `mainElement` because `main` is a reserved word in many contexts.
public func mainElement(
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    .element(applyAttributes(tag: "main", attributes, children: children()))
}

/// HTML `<dialog>` — native modal/non-modal. Open via `el.showModal!()` /
/// `el.show!()` and close via `el.close!()` from Swift (use `Ref<JSObject>`).
/// The `::backdrop` pseudo-element can be styled via the scoped sheet.
public func dialog(
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    .element(applyAttributes(tag: "dialog", attributes, children: children()))
}

/// HTML `<details>` — disclosure widget. Pair with `summary(...)` for the
/// always-visible label.
public func details(
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    .element(applyAttributes(tag: "details", attributes, children: children()))
}

/// HTML `<summary>` — the label child of a `<details>`.
public func summary(
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    .element(applyAttributes(tag: "summary", attributes, children: children()))
}

/// Text-only convenience for `<summary>`.
public func summary(_ text: String, _ attributes: Attribute...) -> VNode {
    .element(applyAttributes(tag: "summary", attributes, children: [.text(text)]))
}

/// HTML `<aside>` landmark.
public func aside(
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    .element(applyAttributes(tag: "aside", attributes, children: children()))
}

/// HTML `<output>` — form result element.
public func output(
    _ attributes: Attribute...,
    @ChildrenBuilder children: () -> [VNode] = { [] }
) -> VNode {
    .element(applyAttributes(tag: "output", attributes, children: children()))
}

/// Text-only convenience for `<output>`.
public func output(_ text: String, _ attributes: Attribute...) -> VNode {
    .element(applyAttributes(tag: "output", attributes, children: [.text(text)]))
}

/// HTML `<hr>` — void thematic break.
public func hr(_ attributes: Attribute...) -> VNode {
    .element(applyAttributes(tag: "hr", attributes))
}

/// Programmatic element factory taking an `[Attribute]` array (the variadic
/// element factories like `div(...)` can't be called with a spliced array).
/// Folds attributes through the same `applyAttributes` path as every other
/// factory, so URL sanitization, `.compound` flattening, and key extraction
/// all behave identically. Used by SwiflowUI primitives and any caller that
/// assembles attributes dynamically.
public func element(
    _ tag: String,
    attributes: [Attribute] = [],
    children: [VNode] = []
) -> VNode {
    .element(applyAttributes(tag: tag, attributes, children: children))
}

// MARK: - Text node builders
public func text(_ string: String) -> VNode { .text(string) }
public func text(_ value: Int) -> VNode { .text(String(value)) }
public func text(_ value: Double) -> VNode { .text(String(value)) }
public func text(_ value: Bool) -> VNode { .text(String(value)) }
