// Sources/App/Weather/Geolocation.swift
//
// A one-shot bridge to the browser's `navigator.geolocation`. This is a browser
// API (not persistence), so it stays in the example rather than the framework.
// It mirrors Swiflow's JS-interop discipline: retain the callback `JSClosure`s
// until one fires, and fail soft — a denied permission or missing API resolves
// to `nil` so the caller just keeps its existing pins.

#if canImport(JavaScriptKit)
import JavaScriptKit
#endif

enum Geolocation {
    /// Ask the browser for the current position once. Resolves to `nil` if
    /// geolocation is unavailable or the user denies/errors out.
    @MainActor
    static func currentPosition() async -> (latitude: Double, longitude: Double)? {
        #if canImport(JavaScriptKit)
        await withCheckedContinuation { (continuation: CheckedContinuation<(latitude: Double, longitude: Double)?, Never>) in
            guard let geolocation = JSObject.global.navigator.object?.geolocation.object else {
                continuation.resume(returning: nil)
                return
            }

            // Retain the handlers across this synchronous setup via a retainer ↔
            // closures cycle; the first to fire breaks it (see SwiflowStore's
            // PersistentStore for the same pattern).
            let retainer = ClosureRetainer()
            let onSuccess = JSClosure { args in
                retainer.releaseAll()
                guard let position = args.first,
                      let lat = position.coords.latitude.number,
                      let lon = position.coords.longitude.number else {
                    continuation.resume(returning: nil)
                    return .undefined
                }
                continuation.resume(returning: (lat, lon))
                return .undefined
            }
            let onError = JSClosure { _ in
                retainer.releaseAll()
                continuation.resume(returning: nil)
                return .undefined
            }
            retainer.closures = [onSuccess, onError]

            _ = geolocation.getCurrentPosition!(JSValue.object(onSuccess), JSValue.object(onError))
        }
        #else
        return nil
        #endif
    }
}

#if canImport(JavaScriptKit)
private final class ClosureRetainer {
    var closures: [JSClosure] = []

    /// Drops the held closures once the geolocation callback has fired, so
    /// JavaScriptKit's WeakRefs GC can collect them. (No manual release() —
    /// it's a deprecated no-op on the default build.) Called by whichever
    /// handler fires first.
    func releaseAll() {
        closures = []
    }
}
#endif
