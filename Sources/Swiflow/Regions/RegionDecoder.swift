// Sources/Swiflow/Regions/RegionDecoder.swift

/// Decodes a region event/error from its raw JSON `String` into a `Decodable`
/// value type. Core defines only this seam; the browser runtime installs a
/// concrete implementation (e.g. one backed by JavaScriptKit's `JSValueDecoder`),
/// and tests install a stub. This keeps core `Swiflow` free of JavaScriptKit
/// and Foundation while still expressing the typed-event contract.
public protocol RegionEventDecoding {
    func decode<E: Decodable>(_ type: E.Type, from json: String) throws -> E
}

/// Ambient install point for the active `RegionEventDecoding`. Set once by the
/// runtime at startup. `MainActor`-isolated because region handlers run on the
/// main actor.
@MainActor
public enum RegionDecoder {
    public static var current: (any RegionEventDecoding)?
}
