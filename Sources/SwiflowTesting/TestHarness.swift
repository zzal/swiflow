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
}
