// Sources/SwiflowWeb/DispatcherBridge.swift

#if canImport(JavaScriptKit)
import JavaScriptKit
import Swiflow

/// Registers a single Swift function as `window.__swiflowDispatch` so the JS
/// driver can route DOM events back to Swift handlers.
///
/// The registered closure expects two arguments from JS:
/// 1. `handlerId: Number` — the integer ID stored in `HandlerRegistry`.
/// 2. `eventPayload: Object` — `{ type: String, targetValue: String? }`.
enum DispatcherBridge {
    /// Strong reference holding the `JSClosure` so it isn't deallocated.
    /// JSClosure-with-Swift-callback documentation: the closure must outlive
    /// every invocation, so we stash it module-private.
    nonisolated(unsafe) private static var installed: JSClosure?

    /// Idempotent: subsequent calls are no-ops. Phase 2a creates exactly one
    /// registry per app; this matches.
    static func installIfNeeded(registry: HandlerRegistry) {
        guard installed == nil else { return }

        let closure = JSClosure { args -> JSValue in
            // Defensive: silently no-op on malformed payloads. The driver
            // (Task 7) is the only caller and always provides both args.
            guard
                args.count >= 2,
                let handlerId = args[0].number.map({ Int($0) }),
                let payload = args[1].object
            else {
                return .undefined
            }

            let type = payload.type.string ?? ""
            let targetValue = payload.targetValue.string

            registry.dispatch(
                id: handlerId,
                event: Event(type: type, targetValue: targetValue)
            )

            // Returning a JSValue from the closure is required by JSClosure's
            // signature; the JS driver doesn't read it. Future phases may
            // surface preventDefault / stopPropagation here.
            return .undefined
        }

        // JavaScriptKit 0.53+ deprecated `.function(closure)`; use `.object`.
        // The JSClosure is implicitly convertible to a JSObject for this
        // purpose since it's no longer a JSFunction subclass.
        JSObject.global.__swiflowDispatch = .object(closure)
        installed = closure
    }
}

#endif
