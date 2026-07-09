// Sources/SwiflowTesting/TestHarness.swift
import Swiflow
import Testing

/// A snapshot of a single element node. Assert against its fields with `#expect`.
public struct TestNode {
    public let tag: String
    public let text: String
    public let attributes: [String: String]
    /// DOM properties set via `.prop()`, `.value()`, `.checked()`, etc.
    /// Each `PropertyValue` is stringified: `.string(s)` → `s`, `.bool(b)` → `"true"`/`"false"`,
    /// `.int(n)` → decimal string, `.double(d)` → Swift `String(d)` representation.
    /// Use `attributes` for HTML attributes; this field covers typed DOM assignments.
    public let properties: [String: String]
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
        guard let (node, data) = renderer.findElements(tag: tag, text: text,
                                                       in: renderer.mountTree).first
        else { return nil }
        return TestNode(
            tag: data.tag,
            text: renderer.textContent(of: node),
            attributes: data.attributes,
            properties: data.properties.mapValues { flattenProperty($0) }
        )
    }

    /// Returns all elements matching `tag` and optional `text`, in document order.
    public func findAll(_ tag: String, text: String? = nil) -> [TestNode] {
        renderer.findElements(tag: tag, text: text, in: renderer.mountTree).map { (node, data) in
            TestNode(
                tag: data.tag,
                text: renderer.textContent(of: node),
                attributes: data.attributes,
                properties: data.properties.mapValues { flattenProperty($0) }
            )
        }
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
