// Sources/SwiflowWeb/Timing.swift
//
// after(_:do:) — a cancellable wrapper around setTimeout/clearTimeout
// for one-shot delayed work. Designed for Component.onAppear:
//
//     dismissTimer = after(2.5) { [weak self] in self?.onDone() }
//
// Cancel from onDisappear (or whenever the work is no longer wanted):
//
//     dismissTimer?.cancel()
//
// The TimerHandle retains the JSClosure for the timer's lifetime so the
// callback isn't deallocated before JS fires it. cancel() clears the
// timeout and drops the closure. See RAFScheduler.swift for the same
// "retain JSClosure on self until JS is done with it" pattern.

#if canImport(JavaScriptKit)
import JavaScriptKit

/// A cancellable scheduled callback. Returned by `after(_:do:)`.
///
/// Retains the underlying `JSClosure` until either `cancel()` is called or
/// the timer fires; `JSClosure` is reference-counted by JavaScriptKit, so
/// dropping the field allows deallocation once JS no longer holds it.
public final class TimerHandle {
    private var handle: JSValue?
    private var closure: JSClosure?

    fileprivate init(handle: JSValue, closure: JSClosure) {
        self.handle = handle
        self.closure = closure
    }

    /// Clear the underlying setTimeout. No-op if already fired or cancelled.
    public func cancel() {
        guard let h = handle else { return }
        _ = JSObject.global.clearTimeout!(h)
        handle = nil
        // Drop the closure — JS won't call it now.
        closure = nil
    }

    /// Called by the fired closure to drop retained state without invoking
    /// clearTimeout (the timer already fired, so there's nothing to clear).
    fileprivate func didFire() {
        handle = nil
        closure = nil
    }
}

/// Schedule `body` to run after `seconds`. Returns a handle; call `cancel()`
/// to prevent the callback from running. Safe to call from `onAppear` and
/// cancel from `onDisappear`.
@MainActor
public func after(_ seconds: Double, do body: @escaping @MainActor () -> Void) -> TimerHandle {
    // Two-phase init: the JSClosure needs a reference to the TimerHandle so
    // that firing can drop retained state, but the handle needs the closure
    // to construct. We capture the handle weakly through a box that's set
    // immediately after construction.
    final class Box { weak var handle: TimerHandle? }
    let box = Box()

    let closure = JSClosure { _ in
        // setTimeout fires on the main thread in browsers; hop back onto
        // MainActor explicitly for the body and cleanup.
        MainActor.assumeIsolated {
            body()
            box.handle?.didFire()
        }
        return .undefined
    }

    let ms = JSValue.number(seconds * 1000)
    let handleValue = JSObject.global.setTimeout!(closure, ms)
    let h = TimerHandle(handle: handleValue, closure: closure)
    box.handle = h
    return h
}
#endif
