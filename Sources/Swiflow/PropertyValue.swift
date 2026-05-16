// Sources/Swiflow/PropertyValue.swift

/// A typed value for a DOM property (the `node[name] = value` domain — distinct
/// from HTML attributes, inline styles, and event handlers).
public enum PropertyValue: Equatable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
}
