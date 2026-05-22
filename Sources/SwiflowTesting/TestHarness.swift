// Sources/SwiflowTesting/TestHarness.swift
import Swiflow

/// A snapshot of a single element node. Assert against its fields with `#expect`.
public struct TestNode {
    public let tag: String
    public let text: String
    public let attributes: [String: String]
    public let properties: [String: PropertyValue]
}

/// Renders `component` into a headless virtual DOM and returns a `TestHarness`.
@MainActor
public func render<C: Component>(_ component: C) -> TestHarness {
    TestHarness(TestRenderer(component))
}

/// Wraps a `TestRenderer` and exposes the public query + interaction API.
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
            properties: data.properties
        )
    }

    /// Returns all elements matching `tag` and optional `text`, in document order.
    public func findAll(_ tag: String, text: String? = nil) -> [TestNode] {
        renderer.findElements(tag: tag, text: text, in: renderer.mountTree).map { (node, data) in
            TestNode(
                tag: data.tag,
                text: renderer.textContent(of: node),
                attributes: data.attributes,
                properties: data.properties
            )
        }
    }

    /// True iff at least one element matches `tag` and optional `text`.
    public func exists(_ tag: String, text: String? = nil) -> Bool {
        !renderer.findElements(tag: tag, text: text, in: renderer.mountTree).isEmpty
    }

    /// Fires a `click` event on the first element matching `tag` (and `text`).
    /// No-op if no matching element has a click handler.
    public func click(_ tag: String, text: String? = nil) {
        renderer.click(tag: tag, text: text)
    }

    /// Fires an `input` event on the element at position `index` among all
    /// elements matching `tag` (default `"input"`). No-op if out-of-bounds
    /// or if the element has no `input` handler.
    public func input(_ tag: String = "input", at index: Int = 0, value: String) {
        renderer.input(tag: tag, at: index, value: value)
    }

    /// Fires a `blur` event on the element at position `index` among all
    /// elements matching `tag` (default `"input"`). No-op if out-of-bounds
    /// or if the element has no `blur` handler.
    public func blur(_ tag: String = "input", at index: Int = 0) {
        renderer.blur(tag: tag, at: index)
    }
}
