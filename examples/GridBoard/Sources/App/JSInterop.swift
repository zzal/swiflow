// Sources/App/JSInterop.swift
//
// The App target's few imperative touches: a monotonic clock, native
// event listeners (Swiflow's EventInfo carries no pointer coordinates),
// and a requestAnimationFrame loop. Every JSClosure is retained for the
// app's lifetime — GridShell never unmounts.
import JavaScriptKit

@MainActor
func nowMs() -> Double {
    let performance = JSObject.global.performance.object!
    return performance.now.function!(this: performance).number ?? 0
}

/// Attaches a native DOM listener and returns the retained closure.
/// Caller stores it (listener lifetime == app lifetime).
@MainActor
@discardableResult
func addNativeListener(_ target: JSObject, _ event: String,
                       _ handler: @escaping (JSValue) -> Void) -> JSClosure {
    let closure = JSClosure { args in
        handler(args.first ?? .undefined)
        return .undefined
    }
    _ = target.addEventListener!(event, closure)
    return closure
}

/// A per-frame driver for playback + the canvas flow layer.
@MainActor
final class RAFLoop {
    private var closure: JSClosure?
    var onFrame: ((Double) -> Void)?

    func start() {
        guard closure == nil else { return }
        let c = JSClosure { [weak self] args in
            self?.onFrame?(args.first?.number ?? 0)
            self?.schedule()
            return .undefined
        }
        closure = c
        schedule()
    }

    private func schedule() {
        guard let closure else { return }
        _ = JSObject.global.requestAnimationFrame!(closure)
    }
}
