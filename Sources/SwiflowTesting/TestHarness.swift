// Sources/SwiflowTesting/TestHarness.swift
import Swiflow
import Testing

/// A LIVE handle to a rendered element (audit VI Wave-2 #2). Wraps the
/// mount-tree node the diff mutates in place, so reads always reflect the
/// CURRENT tree, actions dispatch on THIS element (never re-queried, never
/// first-in-document-order), and `find` scopes to its subtree:
///
///     h.find(role: "textbox", label: "Email")!.type("x").blur()
///
/// A node that a re-render has removed is *detached*: reads return its last
/// committed state, actions record a test Issue (`isAttached` to check).
@MainActor
public struct TestNode {
    let node: MountNode
    let renderer: TestRenderer

    private var elementData: ElementData? {
        if case .element(let data) = node.vnode { return data }
        return nil
    }

    public var tag: String { elementData?.tag ?? "" }
    /// Subtree text content, current as of the last render.
    public var text: String { renderer.textContent(of: node) }
    /// HTML attributes set via `.attr(...)`, `.class(...)`, `.id(...)`.
    public var attributes: [String: String] { elementData?.attributes ?? [:] }
    /// DOM properties set via `.prop()`, `.value()`, `.checked()`, etc.
    /// Each `PropertyValue` is stringified: `.string(s)` → `s`, `.bool(b)` → `"true"`/`"false"`,
    /// `.int(n)` → decimal string, `.double(d)` → Swift `String(d)` representation.
    /// Use `attributes` for HTML attributes; this field covers typed DOM assignments.
    public var properties: [String: String] {
        (elementData?.properties ?? [:]).mapValues { flattenProperty($0) }
    }
    /// Whether this element is still part of the rendered tree.
    public var isAttached: Bool { renderer.isAttached(node) }

    // MARK: Scoped queries

    /// First element matching `tag` (and `text`) WITHIN this node's subtree.
    public func find(_ tag: String, text: String? = nil) -> TestNode? {
        renderer.findElements(tag: tag, text: text, in: node).first
            .map { TestNode(node: $0.0, renderer: renderer) }
    }

    /// All elements matching `tag` (and `text`) within this node's subtree.
    public func findAll(_ tag: String, text: String? = nil) -> [TestNode] {
        renderer.findElements(tag: tag, text: text, in: node)
            .map { TestNode(node: $0.0, renderer: renderer) }
    }

    // MARK: Actions — strict, chainable

    private func record(_ failure: TestRenderer.InteractionFailure?,
                        _ action: String, _ sourceLocation: SourceLocation) {
        guard let failure else { return }
        Issue.record("\(action) dispatched nothing: \(failure)", sourceLocation: sourceLocation)
    }

    /// Fires `click` on THIS element.
    @discardableResult
    public func click(sourceLocation: SourceLocation = #_sourceLocation) -> TestNode {
        record(renderer.dispatch(event: "click", on: node) {
            EventInfo(type: "click", targetValue: $0.value, targetChecked: $0.checked)
        }, "click()", sourceLocation)
        return self
    }

    /// Fires `input` with `targetValue: value` on THIS element.
    @discardableResult
    public func type(_ value: String, sourceLocation: SourceLocation = #_sourceLocation) -> TestNode {
        record(renderer.dispatch(event: "input", on: node) {
            EventInfo(type: "input", targetValue: value, targetChecked: $0.checked)
        }, "type(\"\(value)\")", sourceLocation)
        return self
    }

    /// Fires `blur` on THIS element.
    @discardableResult
    public func blur(sourceLocation: SourceLocation = #_sourceLocation) -> TestNode {
        record(renderer.dispatch(event: "blur", on: node) {
            EventInfo(type: "blur", targetValue: $0.value, targetChecked: $0.checked)
        }, "blur()", sourceLocation)
        return self
    }

    /// Fires `change` with `targetValue: value` on THIS element.
    @discardableResult
    public func change(value: String, sourceLocation: SourceLocation = #_sourceLocation) -> TestNode {
        record(renderer.dispatch(event: "change", on: node) {
            EventInfo(type: "change", targetValue: value, targetChecked: $0.checked)
        }, "change(value: \"\(value)\")", sourceLocation)
        return self
    }

    /// Fires `change` with `targetChecked: checked` on THIS element.
    @discardableResult
    public func check(_ checked: Bool, sourceLocation: SourceLocation = #_sourceLocation) -> TestNode {
        record(renderer.dispatch(event: "change", on: node) {
            EventInfo(type: "change", targetValue: $0.value, targetChecked: checked)
        }, "check(\(checked))", sourceLocation)
        return self
    }

    /// Fires `keydown` carrying `key` on THIS element.
    @discardableResult
    public func press(key: String, sourceLocation: SourceLocation = #_sourceLocation) -> TestNode {
        record(renderer.dispatch(event: "keydown", on: node) {
            EventInfo(type: "keydown", targetValue: $0.value, targetChecked: $0.checked, key: key)
        }, "press(key: \"\(key)\")", sourceLocation)
        return self
    }

    /// Fires an arbitrary event type on THIS element.
    @discardableResult
    public func fire(_ event: String, sourceLocation: SourceLocation = #_sourceLocation) -> TestNode {
        record(renderer.dispatch(event: event, on: node) {
            EventInfo(type: event, targetValue: $0.value, targetChecked: $0.checked)
        }, "fire(\"\(event)\")", sourceLocation)
        return self
    }
}

func flattenProperty(_ value: PropertyValue) -> String {
    switch value {
    case .string(let s): return s
    case .bool(let b):   return b ? "true" : "false"
    case .int(let i):    return String(i)
    case .double(let d): return String(d)
    }
}

/// Renders `component` into a headless virtual DOM and returns a `TestHarness`.
@MainActor
public func render<C: Component>(_ component: C) -> TestHarness {
    TestHarness(TestRenderer(component))
}

/// Wraps a `TestRenderer` and exposes the public query + interaction API.
///
/// > **Fidelity boundary (audit VI Wave-1):** the harness renders, diffs, and
/// > asserts against the DECLARED VNode tree — the real diff, lifecycle, and
/// > handler wiring run, but nothing is ever applied to a DOM. Everything on
/// > the far side of the patch stream is invisible here: `PatchSerializer`,
/// > `JSAdapter`, the JS driver, and any `#if`-JS-gated imperative effect
/// > (`showModal`, focus, scroll). A bug in *applying* a correct declaration
/// > — the class that shipped the `.style()` custom-property miss — cannot be
/// > caught at this layer; that is what the js-driver tests and Playwright
/// > suites are for. Assert what the tree DECLARES, verify what the browser
/// > DOES elsewhere.
@MainActor
public struct TestHarness {
    let renderer: TestRenderer

    init(_ renderer: TestRenderer) {
        self.renderer = renderer
    }

    /// All text content in the rendered tree, concatenated depth-first.
    public var allText: String { renderer.allText }

    /// Returns the first element matching `tag` (and `text`, if supplied).
    /// `text` matches when the element's subtree text content contains the string.
    public func find(_ tag: String, text: String? = nil) -> TestNode? {
        renderer.findElements(tag: tag, text: text, in: renderer.mountTree).first
            .map { TestNode(node: $0.0, renderer: renderer) }
    }

    /// Returns all elements matching `tag` and optional `text`, in document order.
    public func findAll(_ tag: String, text: String? = nil) -> [TestNode] {
        renderer.findElements(tag: tag, text: text, in: renderer.mountTree)
            .map { TestNode(node: $0.0, renderer: renderer) }
    }

    /// First element whose effective ARIA role is `role` — the explicit
    /// `role` attribute, else the implicit WAI-ARIA mapping for the tag
    /// (`button` → button, `a[href]` → link, `input[type=email]` → textbox,
    /// `h1`–`h6` → heading, …). `label` filters by accessible label
    /// (contains-match): `aria-label` → `<label for=id>` → wrapping
    /// `<label>` → the element's own text.
    ///
    ///     h.find(role: "textbox", label: "Email")!.type("x").blur()
    public func find(role: String, label: String? = nil) -> TestNode? {
        renderer.findByRole(role, label: label).first
            .map { TestNode(node: $0.0, renderer: renderer) }
    }

    /// All elements with effective role `role` (and `label`), document order.
    public func findAll(role: String, label: String? = nil) -> [TestNode] {
        renderer.findByRole(role, label: label)
            .map { TestNode(node: $0.0, renderer: renderer) }
    }

    /// First element whose class LIST contains the token `className`
    /// (token match, not substring — `sw-err` never matches `sw-error`).
    public func find(class className: String) -> TestNode? {
        renderer.findByClass(className).first
            .map { TestNode(node: $0.0, renderer: renderer) }
    }

    /// All elements whose class list contains the token `className`.
    public func findAll(class className: String) -> [TestNode] {
        renderer.findByClass(className)
            .map { TestNode(node: $0.0, renderer: renderer) }
    }

    /// First element whose accessible label contains `label`, any role.
    public func find(label: String) -> TestNode? {
        renderer.findByLabel(label).first
            .map { TestNode(node: $0.0, renderer: renderer) }
    }

    /// All elements whose accessible label contains `label`.
    public func findAll(label: String) -> [TestNode] {
        renderer.findByLabel(label)
            .map { TestNode(node: $0.0, renderer: renderer) }
    }

    /// True iff at least one element matches `tag` and optional `text`.
    public func exists(_ tag: String, text: String? = nil) -> Bool {
        !renderer.findElements(tag: tag, text: text, in: renderer.mountTree).isEmpty
    }

    /// Prints and returns a human-readable dump of the rendered tree — one
    /// line per node: `<tag attrs on:[events]>`, quoted text, `▸ Component`
    /// anchors. For ad-hoc inspection while writing a test; `expect(...)`
    /// includes the same dump in its failure messages.
    @discardableResult
    public func debug() -> String {
        let dump = renderer.dump()
        print(dump)
        return dump
    }

    /// Asserts the rendered tree's text contains `text`. On failure records
    /// an Issue that INCLUDES the rendered tree (audit VI Wave-2 #5 —
    /// `#expect(h.find(...) != nil)` said "expected non-nil" and nothing else).
    public func expect(text: String, sourceLocation: SourceLocation = #_sourceLocation) {
        guard !renderer.allText.contains(text) else { return }
        Issue.record(
            """
            expected text \"\(text)\" — not found. Rendered tree:
            \(renderer.dump())
            """,
            sourceLocation: sourceLocation)
    }

    /// Asserts an element matching `tag` (and `text`, if supplied) exists.
    /// On failure records an Issue that includes the rendered tree.
    public func expect(_ tag: String, text: String? = nil,
                       sourceLocation: SourceLocation = #_sourceLocation) {
        guard renderer.findElements(tag: tag, text: text, in: renderer.mountTree).isEmpty
        else { return }
        let textPart = text.map { " with text \"\($0)\"" } ?? ""
        Issue.record(
            """
            expected a <\(tag)>\(textPart) — none found. Rendered tree:
            \(renderer.dump())
            """,
            sourceLocation: sourceLocation)
    }

    /// Records a test failure at the CALLER's line when an interaction could
    /// not dispatch (audit VI Wave-1: interactions used to silently no-op on
    /// a typo'd selector, and the assertion three lines later failed with a
    /// bare "expected non-nil"). The `IfPresent` variants opt back into the
    /// no-op contract for genuinely conditional interactions.
    private func recordIfFailed(_ failure: TestRenderer.InteractionFailure?,
                                _ interaction: String,
                                _ sourceLocation: SourceLocation) {
        guard let failure else { return }
        Issue.record("\(interaction) dispatched nothing: \(failure)", sourceLocation: sourceLocation)
    }

    /// Fires a `click` event on the first element matching `tag` (and `text`).
    /// STRICT: records a test failure (with candidates) when nothing matches
    /// or the match has no click handler — see `clickIfPresent` for the
    /// old no-op contract.
    public func click(_ tag: String, text: String? = nil,
                      sourceLocation: SourceLocation = #_sourceLocation) {
        recordIfFailed(renderer.click(tag: tag, text: text), "click(\"\(tag)\")", sourceLocation)
    }

    /// `click` with the no-op contract: dispatches when the element and
    /// handler exist, silently does nothing otherwise.
    public func clickIfPresent(_ tag: String, text: String? = nil) {
        _ = renderer.click(tag: tag, text: text)
    }

    /// Fires an `input` event on the element at position `index` among all
    /// elements matching `tag` (default `"input"`). STRICT — see `inputIfPresent`.
    public func input(_ tag: String = "input", at index: Int = 0, value: String,
                      sourceLocation: SourceLocation = #_sourceLocation) {
        recordIfFailed(renderer.input(tag: tag, at: index, value: value), "input(\"\(tag)\")", sourceLocation)
    }

    public func inputIfPresent(_ tag: String = "input", at index: Int = 0, value: String) {
        _ = renderer.input(tag: tag, at: index, value: value)
    }

    /// Fires a `blur` event on the element at position `index` among all
    /// elements matching `tag` (default `"input"`). STRICT — see `blurIfPresent`.
    public func blur(_ tag: String = "input", at index: Int = 0,
                     sourceLocation: SourceLocation = #_sourceLocation) {
        recordIfFailed(renderer.blur(tag: tag, at: index), "blur(\"\(tag)\")", sourceLocation)
    }

    public func blurIfPresent(_ tag: String = "input", at index: Int = 0) {
        _ = renderer.blur(tag: tag, at: index)
    }

    /// Fires a `change` event on the element at position `index` among all
    /// elements matching `tag` (default `"select"`) and flushes. STRICT —
    /// see `changeIfPresent`.
    ///
    /// Use for `<select>` and `<textarea>` with `.on(.change)` handlers;
    /// pair with `.input(...)` for `<input>` elements that use `.on(.input)`.
    public func change(_ tag: String = "select", at index: Int = 0, value: String,
                       sourceLocation: SourceLocation = #_sourceLocation) {
        recordIfFailed(renderer.change(tag: tag, at: index, value: value), "change(\"\(tag)\")", sourceLocation)
    }

    public func changeIfPresent(_ tag: String = "select", at index: Int = 0, value: String) {
        _ = renderer.change(tag: tag, at: index, value: value)
    }

    /// Simulates toggling a checkbox/radio input. Dispatches a `change` event
    /// whose `targetChecked` is `checked`, mirroring the browser driver's
    /// payload. STRICT — see `checkIfPresent`.
    public func check(_ tag: String = "input", at index: Int = 0, checked: Bool,
                      sourceLocation: SourceLocation = #_sourceLocation) {
        recordIfFailed(renderer.check(tag: tag, at: index, checked: checked), "check(\"\(tag)\")", sourceLocation)
    }

    public func checkIfPresent(_ tag: String = "input", at index: Int = 0, checked: Bool) {
        _ = renderer.check(tag: tag, at: index, checked: checked)
    }

    /// Fires an arbitrary event type on the matched element (audit VI
    /// Wave-1: keydown/mousedown/etc. previously required digging handlers
    /// out of the body by hand). The payload carries the target's
    /// value/checked snapshot, like every other interaction. STRICT.
    public func fire(_ event: String, on tag: String, text: String? = nil, at index: Int = 0,
                     sourceLocation: SourceLocation = #_sourceLocation) {
        let failure = renderer.dispatch(event: event, tag: tag, text: text, index: index) {
            EventInfo(type: event, targetValue: $0.value, targetChecked: $0.checked)
        }
        recordIfFailed(failure, "fire(\"\(event)\", on: \"\(tag)\")", sourceLocation)
    }

    /// Dispatches a `keydown` whose `key` is passed through verbatim
    /// (`"ArrowDown"`, `"Enter"`, `"Escape"`, …) — pure `EventInfo.key`
    /// passthrough. STRICT.
    public func press(_ tag: String = "input", key: String, at index: Int = 0,
                      sourceLocation: SourceLocation = #_sourceLocation) {
        let failure = renderer.dispatch(event: "keydown", tag: tag, text: nil, index: index) {
            EventInfo(type: "keydown", targetValue: $0.value, targetChecked: $0.checked, key: key)
        }
        recordIfFailed(failure, "press(\"\(tag)\", key: \"\(key)\")", sourceLocation)
    }

    /// Unmounts the rendered tree, firing `onDisappear` parent-first — mirrors
    /// `Swiflow.unmount(into:)` in the browser. Queries after unmount read the
    /// last-rendered tree and are unspecified. Calling `unmount()` again is a no-op.
    public func unmount() { renderer.unmount() }
}
