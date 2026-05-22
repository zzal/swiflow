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
}
