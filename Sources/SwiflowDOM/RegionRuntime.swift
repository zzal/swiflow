// Sources/SwiflowDOM/RegionRuntime.swift
#if canImport(JavaScriptKit)
import JavaScriptKit
import Swiflow

/// The concrete `RegionEventDecoding` for the browser: parse the JSON string
/// with the engine's native `JSON.parse`, then decode the resulting JSValue
/// into the typed `RegionEvent`/`RegionError` via JavaScriptKit's
/// `JSValueDecoder`. Installed into `RegionDecoder.current` at mount. Mirrors
/// the decode pattern in `SwiflowStore/PersistentStore.swift`.
struct SwiflowRegionDecoder: RegionEventDecoding {
    func decode<E: Decodable>(_ type: E.Type, from json: String) throws -> E {
        guard let parse = JSObject.global.JSON.object?.parse.function else {
            throw RegionError(code: "no-json", message: "JSON.parse unavailable")
        }
        let parsed = try parse.throws(json)
        return try JSValueDecoder().decode(E.self, from: parsed)
    }
}
#endif
