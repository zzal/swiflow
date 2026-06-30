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
/// - `environmentOverride`: overrides one or more environment values for a
///   subtree. Created by `withEnvironment(_:_:content:)`. Phase 10+.
/// - `fragment`: a transparent child slot with no DOM node of its own — the
///   runtime form of a builder `if`/`for`. Holds its position even when empty.
///
/// **Sendable:** `VNode` and `ElementData` deliberately do *not* conform to
/// `Sendable` in Phase 1. They transitively hold `EventHandler`, which wraps
/// a non-`@Sendable` closure; deciding whether to require `@Sendable` on
/// handler closures is a Phase 3 concern that depends on the final actor
/// model for `HandlerRegistry`. `EventInfo` is `Sendable` because it carries
/// only value types and may be ferried across isolation boundaries when
/// the dispatcher is wired in Phase 2.
public indirect enum VNode {
    case element(ElementData)
    case text(String)
    case rawHTML(String)
    /// A component anchor. Carries identity (`typeID` + `key`) and a factory
    /// closure consumed at first mount. Subsequent renders with an equal
    /// description at the same child position reuse the existing instance
    /// (Phase 3+ — see `Component` and `ComponentDescription`).
    case component(ComponentDescription)
    /// An environment override wrapping a subtree. Equality compares both the
    /// environment values and the child node; when only the env values change
    /// the diff detects the difference and re-merges the subtree.
    case environmentOverride(EnvironmentValues, VNode)
    /// A transparent grouping of children with no DOM element of its own — the
    /// runtime form of a builder `if` / `if-else` / `for`. It occupies exactly
    /// one stable child slot among its siblings (so toggling/looping never
    /// shifts a sibling) while its children render directly into the nearest
    /// real DOM ancestor. Produced only by `ChildrenBuilder`; pure-virtual
    /// (emits no create/destroy patch — like `.environmentOverride`).
    case fragment([VNode])
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
    /// `Ref<Element>` bindings consumed by Diff at mount/destroy time.
    /// Stored out-of-band — these never participate in the four bag
    /// dictionaries and never become patches. See `Attribute.refBinding`
    /// and the `.ref(_:)` modifier in SwiflowDOM.
    public var refBindings: [AnyRefBinding]
    /// `.task` async effects declared on this node, captured at body-eval time.
    /// Stored out-of-band like `refBindings`: consumed by Diff at mount/update/
    /// destroy and never folded into the four bags or compared in `==`.
    public var taskBindings: [TaskBinding] = []
    /// When true, Swiflow mounts this element's initially-declared children once, then NEVER
    /// reconciles inside it again — an escape hatch for elements that own their own DOM subtree
    /// (custom elements with self-managed light/shadow children, a foreign-painted `<canvas>`, a
    /// third-party widget). The element shell (tag + attributes/properties/style/handlers) is still
    /// reactively reconciled; only the children are left alone. Never serialized — it gates patch
    /// generation on the Swift side only. Set via `VNode.unmanagedChildren()`.
    public var managesOwnChildren: Bool = false
    /// Optional memoization token. When two same-tag elements being diffed both
    /// carry a non-nil, EQUAL `memoKey`, the diff treats the element (and its
    /// entire subtree) as unchanged and skips all reconciliation. Caller's
    /// contract: equal key ⇒ equal rendered element + children. Swift-side only —
    /// excluded from `==` (it is metadata, not rendered shape) and never
    /// serialized into a `Patch`. Set via `VNode.memoKey(_:)`.
    public var memoKey: AnyHashable? = nil

    /// Creates an `ElementData` with the given bags. Every bag defaults to
    /// empty so callers can pass only what they need.
    public init(
        tag: String,
        key: String? = nil,
        attributes: [String: String] = [:],
        properties: [String: PropertyValue] = [:],
        style: [String: String] = [:],
        handlers: [String: EventHandler] = [:],
        children: [VNode] = [],
        refBindings: [AnyRefBinding] = [],
        taskBindings: [TaskBinding] = []
    ) {
        self.tag = tag
        self.key = key
        self.attributes = attributes
        self.properties = properties
        self.style = style
        self.handlers = handlers
        self.children = children
        self.refBindings = refBindings
        self.taskBindings = taskBindings
    }

    /// Manual equality: every field participates EXCEPT `refBindings` and
    /// `taskBindings`. Both carry closures (never `Equatable`) and are
    /// out-of-band lifecycle metadata — not part of the rendered DOM shape.
    /// Two ElementData values describing the same element compare equal
    /// regardless of which side carries Ref or task bindings.
    public static func == (lhs: ElementData, rhs: ElementData) -> Bool {
        lhs.tag == rhs.tag
            && lhs.key == rhs.key
            && lhs.attributes == rhs.attributes
            && lhs.properties == rhs.properties
            && lhs.style == rhs.style
            && lhs.handlers == rhs.handlers
            && lhs.managesOwnChildren == rhs.managesOwnChildren
            && lhs.children == rhs.children
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
/// user closure. `EventInfo` is the runtime payload (type + value/checked
/// snapshots); the `Event` enum selects which event to listen for.
public struct EventInfo: Equatable, Sendable {
    /// DOM event name (e.g. `"click"`, `"input"`, `"change"`).
    public let type: String

    /// Snapshot of `event.target.value` for form inputs; `nil` for events
    /// without a value-bearing target.
    public let targetValue: String?

    /// Snapshot of `event.target.checked` for checkbox/radio inputs;
    /// `nil` for events without a `checked` property on the target.
    public let targetChecked: Bool?

    /// True when the event's target IS the element the handler is bound to
    /// (`event.target === event.currentTarget`) — the event originated on this
    /// element itself rather than bubbling up from a descendant. Enables
    /// "did the user act on the element itself, not its contents?" patterns,
    /// e.g. backdrop-click-to-dismiss on a `<dialog>` (a backdrop click targets
    /// the dialog; a click on its content targets a child).
    public let isSelfTarget: Bool

    /// For keyboard events (`keydown`/`keyup`/`keypress`), `event.key` — the value of
    /// the key pressed (e.g. `"ArrowDown"`, `"Enter"`, `"Escape"`, `"Tab"`, `"a"`); `nil`
    /// for non-keyboard events. Enables keyboard navigation (combobox/menu roving,
    /// shortcuts) without wiring a listener per key.
    public let key: String?

    /// Modifier-key state at the time of the event. Present on keyboard *and* mouse
    /// events, so a `.click` handler can branch on `metaKey`/`shiftKey` too (Cmd+click,
    /// Shift+select); `false` for events without modifier state.
    public let shiftKey: Bool
    public let ctrlKey: Bool
    public let altKey: Bool
    public let metaKey: Bool

    /// Raw JSON payload for custom events (e.g. a region's `sf:event`/`sf:error`).
    /// `nil` for ordinary DOM events. Carried as a `String` (not a `JSObject`) so
    /// `EventInfo` stays `Sendable` and core `Swiflow` stays free of JavaScriptKit;
    /// typed decoding happens in the Region DSL via `RegionEventDecoding`.
    public let detail: String?

    public init(
        type: String,
        targetValue: String? = nil,
        targetChecked: Bool? = nil,
        isSelfTarget: Bool = false,
        key: String? = nil,
        shiftKey: Bool = false,
        ctrlKey: Bool = false,
        altKey: Bool = false,
        metaKey: Bool = false,
        detail: String? = nil
    ) {
        self.type = type
        self.targetValue = targetValue
        self.targetChecked = targetChecked
        self.isSelfTarget = isSelfTarget
        self.key = key
        self.shiftKey = shiftKey
        self.ctrlKey = ctrlKey
        self.altKey = altKey
        self.metaKey = metaKey
        self.detail = detail
    }

    /// `targetValue` parsed as an `Int`; `nil` if absent or unparseable.
    public var targetIntValue: Int? {
        targetValue.flatMap(Int.init)
    }

    /// `targetValue` parsed as a `Double`; `nil` if absent or unparseable.
    public var targetDoubleValue: Double? {
        targetValue.flatMap(Double.init)
    }
}

extension VNode: Equatable {
    public static func == (lhs: VNode, rhs: VNode) -> Bool {
        switch (lhs, rhs) {
        case (.text(let a), .text(let b)): return a == b
        case (.rawHTML(let a), .rawHTML(let b)): return a == b
        case (.element(let a), .element(let b)): return a == b
        case (.component(let a), .component(let b)): return a == b
        case (.environmentOverride(let envA, let a), .environmentOverride(let envB, let b)):
            return envA == envB && a == b
        case (.fragment(let a), .fragment(let b)): return a == b
        default: return false
        }
    }
}
