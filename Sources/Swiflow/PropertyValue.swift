// Sources/Swiflow/PropertyValue.swift

/// A typed value for a DOM property (the `node[name] = value` domain — distinct
/// from HTML attributes, inline styles, and event handlers).
public enum PropertyValue: Equatable, Sendable {
    /// A string property (e.g. `input.value`).
    case string(String)
    /// An integer property (e.g. `select.selectedIndex`).
    case int(Int)
    /// A floating-point property (e.g. `video.currentTime`).
    case double(Double)
    /// A boolean property (e.g. `input.checked`, `input.disabled`).
    case bool(Bool)
}

extension PropertyValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = .string(value)
    }
}

extension PropertyValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        self = .bool(value)
    }
}

extension PropertyValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self = .int(value)
    }
}

extension PropertyValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self = .double(value)
    }
}
