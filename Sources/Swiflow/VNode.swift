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
/// - `component`: a Component anchor — instantiates and renders a reactive
///   `Component` whose `body` is diffed against the previously-mounted
///   subtree. Phase 3+.
///
/// **Sendable:** `VNode` and `ElementData` deliberately do *not* conform to
/// `Sendable` in Phase 1. They transitively hold `EventHandler`, which wraps
/// a non-`@Sendable` closure; deciding whether to require `@Sendable` on
/// handler closures is a Phase 3 concern that depends on the final actor
/// model for `HandlerRegistry`. `EventInfo` is `Sendable` because it carries
/// only value types and may be ferried across isolation boundaries when
/// the dispatcher is wired in Phase 2.
public indirect enum VNode: Equatable {
    case element(ElementData)
    case text(String)
    case rawHTML(String)
    /// A component anchor. Carries identity (`typeID` + `key`) and a factory
    /// closure consumed at first mount. Subsequent renders with an equal
    /// description at the same child position reuse the existing instance
    /// (Phase 3+ — see `Component` and `ComponentDescription`).
    case component(ComponentDescription)
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
    /// HTML tag name (e.g. `"div"`, `"input"`). Lowercase by convention.
    public let tag: String
    /// Optional stable identity used by the keyed children diff. When `nil`,
    /// the indexed diff strategy is used instead.
    public var key: String?
    /// HTML attributes (set via `Element.setAttribute`).
    public var attributes: [String: String]
    /// DOM properties (set via direct property assignment, e.g. `input.value`).
    public var properties: [String: PropertyValue]
    /// Inline style declarations (set via `element.style[name]`).
    public var style: [String: String]
    /// Event listeners, keyed by event name (e.g. `"click"`).
    public var handlers: [String: EventHandler]
    /// Child virtual nodes in document order.
    public let children: [VNode]

    /// Creates an `ElementData` with the given bags. Every bag defaults to
    /// empty so callers can pass only what they need.
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
/// is `(EventInfo) -> Void`, not `@Sendable (EventInfo) -> Void`; tightening
/// that is deferred to Phase 3 once the actor model for the dispatcher is fixed.
public struct EventHandler: Equatable {
    /// Monotonic identifier assigned by `HandlerRegistry`. Forms the basis of
    /// equality and is the value sent across the JS bridge.
    public let id: Int
    /// The Swift closure invoked when the corresponding DOM event fires.
    public let invoke: (EventInfo) -> Void

    /// Wraps a closure with its registry-assigned ID. Prefer
    /// `HandlerRegistry.register(_:)` over calling this directly.
    public init(id: Int, invoke: @escaping (EventInfo) -> Void) {
        self.id = id
        self.invoke = invoke
    }

    /// Two handlers are equal iff their `id`s match. Closures are unequatable.
    public static func == (lhs: EventHandler, rhs: EventHandler) -> Bool {
        lhs.id == rhs.id
    }
}

/// Runtime DOM event payload surfaced into Swift handlers.
///
/// The two-argument `.on(_:perform:)` modifier passes one of these to the
/// user closure. The event-name catalog (`Event` enum, added in a later task)
/// selects WHICH event to listen for; `EventInfo` carries the runtime payload
/// (type string, the target's value for form inputs).
public struct EventInfo: Equatable, Sendable {
    /// DOM event name (e.g. `"click"`, `"input"`).
    public let type: String
    /// Convenience snapshot of `event.target.value` for form inputs; `nil` for
    /// events without a value-bearing target.
    public let targetValue: String?

    public init(type: String, targetValue: String? = nil) {
        self.type = type
        self.targetValue = targetValue
    }
}
