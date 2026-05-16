// Sources/Swiflow/VNode.swift

/// The fundamental unit of the Swiflow virtual DOM.
///
/// `VNode` is a tagged enum: each render produces a fresh tree of `VNode`
/// values, and the diff engine compares it against the previously committed
/// tree to produce a list of `Patch`es.
///
/// - `element`: a tagged HTML-like node (see `ElementData`).
/// - `text`: a text node. Always rendered via `textContent` for XSS safety.
/// - `rawHTML`: an escape hatch that renders via `innerHTML`. The name is
///   loud on purpose — searching for `rawHTML(` enumerates every audit site.
///
/// **Sendable:** `VNode` and `ElementData` deliberately do *not* conform to
/// `Sendable` in Phase 1. They transitively hold `EventHandler`, which wraps
/// a non-`@Sendable` closure; deciding whether to require `@Sendable` on
/// handler closures is a Phase 3 concern that depends on the final actor
/// model for `HandlerRegistry`. `Event` is `Sendable` because it carries
/// only value types and may be ferried across isolation boundaries when
/// the dispatcher is wired in Phase 2.
public indirect enum VNode: Equatable {
    case element(ElementData)
    case text(String)
    case rawHTML(String)
}

/// The payload of an `.element` VNode. Four separate bags model the four
/// distinct DOM categories, matching how Snabbdom / Vue / Inferno structure
/// their VNodes:
///
/// - `attributes`: set via `Element.setAttribute(name, value)`.
/// - `properties`: set via direct property assignment, e.g. `input.value = …`.
/// - `style`: inline style declarations, set via `element.style[name] = …`.
/// - `handlers`: event listeners. Keys are event names like `"click"`.
public struct ElementData: Equatable {
    public let tag: String
    public let key: String?
    public let attributes: [String: String]
    public let properties: [String: PropertyValue]
    public let style: [String: String]
    public let handlers: [String: EventHandler]
    public let children: [VNode]

    public init(
        tag: String,
        key: String? = nil,
        attributes: [String: String] = [:],
        properties: [String: PropertyValue] = [:],
        style: [String: String] = [:],
        handlers: [String: EventHandler] = [:],
        children: [VNode] = []
    ) {
        self.tag = tag
        self.key = key
        self.attributes = attributes
        self.properties = properties
        self.style = style
        self.handlers = handlers
        self.children = children
    }
}

/// An event handler keyed by its `id` in `HandlerRegistry`.
///
/// The closure itself is intentionally not part of equality (Swift closures
/// are unequatable); two handlers with the same `id` are considered equal
/// because the registry's monotonic ID is the identity.
///
/// **Sendable:** intentionally not `Sendable` in Phase 1. The closure type
/// is `(Event) -> Void`, not `@Sendable (Event) -> Void`; tightening that
/// is deferred to Phase 3 once the actor model for the dispatcher is fixed.
public struct EventHandler: Equatable {
    public let id: Int
    public let invoke: (Event) -> Void

    public init(id: Int, invoke: @escaping (Event) -> Void) {
        self.id = id
        self.invoke = invoke
    }

    public static func == (lhs: EventHandler, rhs: EventHandler) -> Bool {
        lhs.id == rhs.id
    }
}

/// A DOM event surfaced into Swift.
///
/// Phase 1 keeps `Event` deliberately minimal. Phase 3 will extend it with
/// keyboard/pointer specifics as `Component` lifecycle wires up.
public struct Event: Equatable, Sendable {
    public let type: String
    public let targetValue: String?

    public init(type: String, targetValue: String? = nil) {
        self.type = type
        self.targetValue = targetValue
    }
}
