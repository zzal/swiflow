// Sources/Swiflow/DSL/Modifiers.swift

/// A single modifier passed to an element factory (e.g. `div(.class("row"))`).
/// Each case maps directly to one of `ElementData`'s bags.
public enum Attribute {
    case attribute(name: String, value: String)
    case property(name: String, value: PropertyValue)
    case style(name: String, value: String)
    case handler(event: String, value: EventHandler)
    case key(String)

    // Convenience factories.

    public static func attr(_ name: String, _ value: String) -> Attribute {
        .attribute(name: name, value: value)
    }

    public static func `class`(_ value: String) -> Attribute {
        .attribute(name: "class", value: value)
    }

    public static func id(_ value: String) -> Attribute {
        .attribute(name: "id", value: value)
    }

    public static func prop(_ name: String, _ value: PropertyValue) -> Attribute {
        .property(name: name, value: value)
    }

    public static func style(_ name: String, _ value: String) -> Attribute {
        .style(name: name, value: value)
    }

    public static func on(_ event: String, _ handler: EventHandler) -> Attribute {
        .handler(event: event, value: handler)
    }
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
            attrs[name] = value
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
