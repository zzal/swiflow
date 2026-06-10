// Sources/Swiflow/DSL/Modifiers.swift

/// A single modifier passed to an element factory (e.g. `div(.class("row"))`).
/// Each case maps directly to one of `ElementData`'s bags.
public enum Attribute {
    /// An HTML attribute (`setAttribute`).
    case attribute(name: String, value: String)
    /// A DOM property (typed; assigned directly on the node).
    case property(name: String, value: PropertyValue)
    /// An inline-style declaration.
    case style(name: String, value: String)
    /// An event-listener registration.
    case handler(event: String, value: EventHandler)
    /// A stable identity used by the keyed children diff.
    case key(String)
    /// Internal sentinel produced by overloads that need to *omit* an
    /// attribute given a runtime condition (e.g. `attr(_:_:Bool)` with
    /// `false`). `applyAttributes` drops these during the fold; they
    /// never reach `ElementData`. Not for general use.
    case skip
    /// Composite of multiple attribute effects produced by a single modifier
    /// (e.g. `.value($text)` writes both a `value` property AND an `.input`
    /// handler). `applyAttributes` recursively flattens these during the
    /// fold; composites never reach `ElementData`.
    case compound([Attribute])
    /// Binds the host element's DOM-side handle into a `Ref<Element>` at
    /// mount time and clears it at destroy. Stored on
    /// `ElementData.refBindings` and consumed out-of-band by Diff; never
    /// folded into the four normal bags. Produced by the `.ref(_:)`
    /// modifier in SwiflowDOM.
    case refBinding(AnyRefBinding)

    // Convenience factories.

    /// Shorthand for `.attribute(name:value:)`.
    public static func attr(_ name: String, _ value: String) -> Attribute {
        .attribute(name: name, value: value)
    }

    /// Sets an HTML attribute with an `Int` value (stringified).
    public static func attr(_ name: String, _ value: Int) -> Attribute {
        .attribute(name: name, value: String(value))
    }

    /// Sets an HTML attribute with a `Double` value (stringified).
    public static func attr(_ name: String, _ value: Double) -> Attribute {
        .attribute(name: name, value: String(value))
    }

    /// Sets an HTML boolean attribute. HTML boolean attributes are
    /// presence-or-absent (`disabled`, `checked`, `readonly`). Emits a
    /// presence-only attribute (empty-string value) when `value` is
    /// `true`; omits the attribute entirely when `value` is `false`.
    /// Matches HTML semantics — no call-site gating required.
    public static func attr(_ name: String, _ value: Bool) -> Attribute {
        value ? .attribute(name: name, value: "") : .skip
    }

    /// Convenience for `data-*` attributes. `.data("user-id", "42")` emits
    /// `data-user-id="42"`.
    public static func data(_ name: String, _ value: String) -> Attribute {
        .attribute(name: "data-\(name)", value: value)
    }

    /// Sets the `class` attribute. Backticks because `class` is a Swift
    /// keyword.
    public static func `class`(_ value: String) -> Attribute {
        .attribute(name: "class", value: value)
    }

    /// Sets the `id` attribute.
    public static func id(_ value: String) -> Attribute {
        .attribute(name: "id", value: value)
    }

    /// Shorthand for `.property(name:value:)`.
    public static func prop(_ name: String, _ value: PropertyValue) -> Attribute {
        .property(name: name, value: value)
    }

    /// Shorthand for `.style(name:value:)`.
    public static func style(_ name: String, _ value: String) -> Attribute {
        .style(name: name, value: value)
    }

    public static func transition(_ value: String) -> Attribute {
        .style(name: "transition", value: value)
    }

    public static func animation(_ value: String) -> Attribute {
        .style(name: "animation", value: value)
    }

    public static func cssVar(_ name: String, _ value: String) -> Attribute {
        .style(name: name, value: value)
    }

    // No explicit `static func key(_:)` is needed — `case key(String)`
    // auto-synthesizes a constructor with the same call-site syntax
    // (`Attribute.key("k1")`). Declaring one explicitly is a redeclaration
    // error.
}

/// Folds a list of `Attribute`s into the four bags + key of an `ElementData`.
/// Later attributes of the same key override earlier ones — this matches the
/// "last write wins" intuition of standard DOM property assignment.
func applyAttributes(
    tag: String,
    _ attributes: [Attribute],
    children: [VNode] = []
) -> ElementData {
    var attrs: [String: String] = [:]
    var props: [String: PropertyValue] = [:]
    var styles: [String: String] = [:]
    var handlers: [String: EventHandler] = [:]
    var key: String? = nil
    var refBindings: [AnyRefBinding] = []

    // Nested helper so `.compound` can recurse naturally. The closure
    // captures the local bags by reference (`inout` semantics via the
    // enclosing-scope vars) and mutates them in place.
    func process(_ attribute: Attribute) {
        switch attribute {
        case .attribute(let name, let value):
            // URL-bearing attributes (href, src, action, formaction) route
            // through URLSanitizer before reaching the bag (case-insensitive
            // on the name); non-URL attributes pass through. A rejected URL
            // returns nil and the attribute is dropped — see
            // URLSanitizer.resolvedAttributeValue.
            if let resolved = URLSanitizer.resolvedAttributeValue(name: name, value: value) {
                attrs[name] = resolved
            }
        case .property(let name, let value):
            props[name] = value
        case .style(let name, let value):
            styles[name] = value
        case .handler(let event, let value):
            handlers[event] = value
        case .key(let value):
            key = value
        case .skip:
            return
        case .compound(let inner):
            for child in inner { process(child) }
        case .refBinding(let binding):
            // Refs are stashed on ElementData out-of-band — they don't
            // belong in any of the four bags and never become patches.
            // Diff.mount/destroy consume them directly via
            // `data.refBindings`.
            refBindings.append(binding)
        }
    }

    for attribute in attributes {
        process(attribute)
    }

    return ElementData(
        tag: tag,
        key: key,
        attributes: attrs,
        properties: props,
        style: styles,
        handlers: handlers,
        children: children,
        refBindings: refBindings
    )
}
