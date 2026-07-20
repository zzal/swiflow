// Sources/SwiflowDOM/DispatcherBridge.swift

#if canImport(JavaScriptKit)
import JavaScriptKit
import Swiflow

/// Registers a single Swift function as `window.__swiflowDispatch` so the JS
/// driver can route DOM events back to Swift handlers.
///
/// The registered closure expects two arguments from JS:
/// 1. `handlerId: Number` — the integer ID stored in `HandlerRegistry`.
/// 2. `eventPayload: Object` — `{ type, targetValue?, targetChecked?, isSelfTarget, fromInteractiveDescendant, detail?,
///    key?, shiftKey, ctrlKey, altKey, metaKey }`.
enum DispatcherBridge {
    /// Held for ownership clarity / idempotency-checking (see `install()`
    /// below), not because it's what keeps the closure callable —
    /// `JSClosure.init` self-registers into JavaScriptKit's static
    /// `sharedClosures` table independent of this field.
    @MainActor private static var installed: JSClosure?

    /// Idempotent: subsequent calls are no-ops. One JSClosure services all
    /// roots — handler IDs are globally unique across all `HandlerRegistry`
    /// instances, so `HandlerRegistry.dispatchGlobal` routes
    /// correctly regardless of which root registered the handler.
    @MainActor
    static func install() {
        guard installed == nil else { return }

        let closure = JSClosure { args -> JSValue in
            guard
                args.count >= 2,
                // Int(exactly:) — never the trapping Int(Double): this global is
                // reachable by ANY page script, and on wasm32 Int is 32-bit, so a
                // NaN/Infinity/±2^31-exceeding number (a timestamp!) would otherwise
                // kill the whole app. Malformed calls fall through to .undefined.
                let handlerId = args[0].number.flatMap({ Int(exactly: $0) }),
                let payload = args[1].object
            else {
                return .undefined
            }

            let type = payload.type.string ?? ""
            let targetValue = payload.targetValue.string
            let targetChecked = payload.targetChecked.boolean
            let isSelfTarget = payload.isSelfTarget.boolean ?? false
            let fromInteractiveDescendant = payload.fromInteractiveDescendant.boolean ?? false
            let key = payload.key.string
            let shiftKey = payload.shiftKey.boolean ?? false
            let ctrlKey = payload.ctrlKey.boolean ?? false
            let altKey = payload.altKey.boolean ?? false
            let metaKey = payload.metaKey.boolean ?? false
            let detail = payload.detail.string

            MainActor.assumeIsolated {
                HandlerRegistry.dispatchGlobal(
                    id: handlerId,
                    event: EventInfo(
                        type: type,
                        targetValue: targetValue,
                        targetChecked: targetChecked,
                        isSelfTarget: isSelfTarget,
                        fromInteractiveDescendant: fromInteractiveDescendant,
                        key: key,
                        shiftKey: shiftKey,
                        ctrlKey: ctrlKey,
                        altKey: altKey,
                        metaKey: metaKey,
                        detail: detail
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
