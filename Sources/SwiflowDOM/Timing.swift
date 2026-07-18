// Sources/SwiflowDOM/Timing.swift
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
// The callback is a JSOneshotClosure: it self-releases from
// JavaScriptKit's static sharedClosures table after its single firing, so
// a fired timer leaves nothing pinned. A CANCELLED timer never fires, so
// cancel() must (and does) release the closure explicitly — with a plain
// JSClosure, dropping the Swift reference would leave the entry pinned in
// the static table forever (the leak class found in RAFScheduler via
// GridBoard playback). TimerHandle also cancels itself on deinit, so
// dropping a handle without calling cancel() still clears the underlying
// setTimeout and releases the closure.

#if canImport(JavaScriptKit)
import JavaScriptKit

/// A cancellable scheduled callback. Returned by `after(_:do:)`.
///
/// Holds the underlying `JSOneshotClosure` and setTimeout handle until
/// either `cancel()` is called or the timer fires; see the file-level
/// comment for the closure-release contract.
///
/// `@MainActor`-isolated (all JS access here — `clearTimeout` — must run on
/// the main thread) with an isolated `deinit`, so dropping a handle without
/// calling `cancel()` still clears the pending timeout instead of letting it
/// fire after the owner is gone.
@MainActor
public final class TimerHandle {
    private var handle: JSValue?
    private var closure: JSOneshotClosure?

    fileprivate init(handle: JSValue, closure: JSOneshotClosure) {
        self.handle = handle
        self.closure = closure
    }

    /// Clear the underlying setTimeout. No-op if already fired or cancelled.
    public func cancel() {
        guard let h = handle else { return }
        _ = JSObject.global.clearTimeout!(h)
        handle = nil
        // A cancelled one-shot never fires, so it never self-releases —
        // release it here or its sharedClosures entry stays pinned forever.
        closure?.release()
        closure = nil
    }

    /// Called by the fired closure to drop retained state without invoking
    /// clearTimeout (the timer already fired, so there's nothing to clear).
    fileprivate func didFire() {
        handle = nil
        // The one-shot self-released on invocation; just drop the reference.
        closure = nil
    }

    /// Safety net for handles dropped without an explicit `cancel()` call
    /// (e.g. a component torn down without running its `onDisappear`):
    /// clears the pending JS timeout instead of leaving it to fire against
    /// a gone owner.
    isolated deinit {
        cancel()
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

    let closure = JSOneshotClosure { _ in
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
