// Sources/Swiflow/Regions/RegionWire.swift
//
// The wire-protocol string constants shared by the typed and inline region
// faces. Centralized so the host (Swift) and the Plan 2 browser runtime
// (custom element + JS driver) can't drift on these names. Internal — not part
// of the public API surface.
enum RegionWire {
    static let tag        = "sf-region"
    static let sourceAttr = "data-source"
    static let propsKey   = "sfProps"
    static let eventName  = "sf:event"
    static let errorName  = "sf:error"
}
