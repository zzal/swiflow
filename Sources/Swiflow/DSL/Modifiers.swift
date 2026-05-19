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

    // Convenience factories.

    /// Shorthand for `.attribute(name:value:)`.
    public static func attr(_ name: String, _ value: String) -> Attribute {
        .attribute(name: name, value: value)
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

    /// Shorthand for `.handler(event:value:)`.
    public static func on(_ event: String, _ handler: EventHandler) -> Attribute {
        .handler(event: event, value: handler)
    }

    // No explicit `static func key(_:)` is needed — `case key(String)`
    // auto-synthesizes a constructor with the same call-site syntax
    // (`Attribute.key("k1")`). Declaring one explicitly is a redeclaration
    // error.
}

/// Folds a list of `Attribute`s into the four bags + key of an `ElementData`.
/// Later attributes of the same key override earlier ones — this matches the
/// "last write wins" intuition of standard DOM property assignment.
public func applyAttributes(
    tag: String,
    _ attributes: [Attribute],
    children: [VNode] = []
) -> ElementData {
    var attrs: [String: String] = [:]
    var props: [String: PropertyValue] = [:]
    var styles: [String: String] = [:]
    var handlers: [String: EventHandler] = [:]
    var key: String? = nil

    for attribute in attributes {
        switch attribute {
        case .attribute(let name, let value):
            // URL-bearing attributes (href, src, action, formaction) route
            // through URLSanitizer before reaching the bag. The check is
            // case-insensitive on the attribute name. Non-URL attributes
            // pass through unchanged.
            if URLSanitizer.urlAttributeNames.contains(name.lowercased()) {
                if let sanitized = URLSanitizer.sanitize(value) {
                    attrs[name] = sanitized
                } else {
                    // Drop the attribute entirely. Debug-mode notice; Task 2
                    // will reword this comment but keep the print as-is.
                    #if DEBUG
                    print("[Swiflow] URLSanitizer rejected \(name)=\"\(value)\" — attribute dropped. Use VNode.rawHTML for the rare case where unsanitized URLs are intentional.")
                    #endif
                }
            } else {
                attrs[name] = value
            }
        case .property(let name, let value):
            props[name] = value
        case .style(let name, let value):
            styles[name] = value
        case .handler(let event, let value):
            handlers[event] = value
        case .key(let value):
            key = value
        }
    }

    return ElementData(
        tag: tag,
        key: key,
        attributes: attrs,
        properties: props,
        style: styles,
        handlers: handlers,
        children: children
    )
}
