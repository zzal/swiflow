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
