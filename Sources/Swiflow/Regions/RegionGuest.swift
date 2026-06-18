// Sources/Swiflow/Regions/RegionGuest.swift

/// A decodable event a region guest emits back to the host. Conformers are
/// plain `Decodable` value types; the framework decodes the `sf:event`
/// payload into this type via `RegionEventDecoding`.
public protocol RegionEvent: Decodable {}

/// The contract for one external wasm guest: its served `source`, the `Props`
/// the host sends in, and the `Event` it emits out. Declaring a guest type
/// once lets every `.onEvent` handler *infer* its event type — no annotation.
public protocol RegionGuest {
    associatedtype Props: Encodable
    associatedtype Event: RegionEvent
    /// URL/path of the guest wasm asset (e.g. `"regions/scene.wasm"`).
    static var source: String { get }
}

/// The payload of a region's `sf:error` event.
public struct RegionError: Decodable, Error, Equatable {
    public let code: String
    public let message: String
    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}
