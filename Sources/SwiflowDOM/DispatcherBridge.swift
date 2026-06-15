// Sources/SwiflowDOM/DispatcherBridge.swift

#if canImport(JavaScriptKit)
import JavaScriptKit
import Swiflow

/// Registers a single Swift function as `window.__swiflowDispatch` so the JS
/// driver can route DOM events back to Swift handlers.
///
/// The registered closure expects two arguments from JS:
/// 1. `handlerId: Number` — the integer ID stored in `HandlerRegistry`.
/// 2. `eventPayload: Object` — `{ type, targetValue?, targetChecked?, isSelfTarget }`.
enum DispatcherBridge {
    /// Strong reference holding the `JSClosure` so it isn't deallocated.
    nonisolated(unsafe) private static var installed: JSClosure?

    /// Idempotent: subsequent calls are no-ops. One JSClosure services all
    /// roots — handler IDs are globally unique across all `HandlerRegistry`
    /// instances (Phase 13c), so `HandlerRegistry.dispatchGlobal` routes
    /// correctly regardless of which root registered the handler.
    static func install() {
        guard installed == nil else { return }

        let closure = JSClosure { args -> JSValue in
            guard
                args.count >= 2,
                let handlerId = args[0].number.map({ Int($0) }),
                let payload = args[1].object
            else {
                return .undefined
            }

            let type = payload.type.string ?? ""
            let targetValue = payload.targetValue.string
            let targetChecked = payload.targetChecked.boolean
            let isSelfTarget = payload.isSelfTarget.boolean ?? false

            MainActor.assumeIsolated {
                HandlerRegistry.dispatchGlobal(
                    id: handlerId,
                    event: EventInfo(
                        type: type,
                        targetValue: targetValue,
                        targetChecked: targetChecked,
                        isSelfTarget: isSelfTarget
                    )
                )
            }

            return .undefined
        }

        JSObject.global.__swiflowDispatch = .object(closure)
        installed = closure
    }
}

#endif
