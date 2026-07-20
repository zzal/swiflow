// Sources/SwiflowTiming/Timing.swift
//
// after(_:do:) — a cancellable one-shot timer for delayed work. Designed
// for Component.onAppear:
//
//     dismissTimer = after(2.5) { [weak self] in self?.onDone() }
//
// Cancel from onDisappear (or whenever the work is no longer wanted):
//
//     dismissTimer?.cancel()
//
// Split keyed on arch(wasm32), NOT canImport(JavaScriptKit): JavaScriptKit
// is an unconditional dependency, so canImport is TRUE on host — the wasm
// branch would compile on macOS and trap at `JSObject.global.setTimeout`
// the moment a host test schedules a timer. Host builds get `ManualTimers`,
// a test-driven queue, so components that arm timers can mount and be
// exercised in a host harness.

#if arch(wasm32)
import JavaScriptKit

// The callback is a JSOneshotClosure: it self-releases from JavaScriptKit's
// static sharedClosures table after its single firing, so a fired timer
// leaves nothing pinned. A CANCELLED timer never fires, so cancel() must
// (and does) release the closure explicitly — with a plain JSClosure,
// dropping the Swift reference would leave the entry pinned in the static
// table forever. TimerHandle also cancels itself on deinit, so dropping a
// handle without calling cancel() still clears the underlying setTimeout
// and releases the closure.

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

#else

/// A cancellable scheduled callback. Returned by `after(_:do:)`.
///
/// Host builds have no event loop driving timers; the callback fires only
/// when a test advances `ManualTimers`. Cancels itself on deinit, matching
/// the wasm contract.
@MainActor
public final class TimerHandle {
    private let id: UInt64

    fileprivate init(id: UInt64) {
        self.id = id
    }

    /// Drop the pending callback. No-op if already fired or cancelled.
    public func cancel() {
        ManualTimers.cancel(id)
    }

    isolated deinit {
        cancel()
    }
}

/// Schedule `body` to run after `seconds` of `ManualTimers` time. Returns a
/// handle; call `cancel()` to prevent the callback from running.
@MainActor
public func after(_ seconds: Double, do body: @escaping @MainActor () -> Void) -> TimerHandle {
    TimerHandle(id: ManualTimers.schedule(seconds, body))
}

/// The host-side timer queue behind `after(_:do:)`, advanced manually from
/// tests (the `ManualClock` pattern). Process-global: a suite that drives it
/// must own it for the test process — `reset()` before each test.
@MainActor
public enum ManualTimers {
    private struct Entry {
        let id: UInt64
        var remaining: Double
        let body: @MainActor () -> Void
    }

    private static var entries: [Entry] = []
    private static var nextID: UInt64 = 1

    /// Timers scheduled and not yet fired or cancelled.
    public static var pendingCount: Int { entries.count }

    /// Advance every pending timer by `seconds`, firing the ones that come
    /// due in due order. A body that schedules a new timer sees it join the
    /// queue with its full duration — never fired within the same call. A
    /// body that cancels another ALREADY-DUE timer does not stop it from
    /// firing in this call.
    public static func advance(by seconds: Double) {
        // Sub-nanosecond tolerance: repeated Double subtraction leaves
        // residue (4 − 3.9 − 0.1 > 0), which must not keep a timer pending.
        let epsilon = 1e-9
        for i in entries.indices { entries[i].remaining -= seconds }
        let due = entries.filter { $0.remaining <= epsilon }.sorted { $0.remaining < $1.remaining }
        entries.removeAll { $0.remaining <= epsilon }
        for entry in due { entry.body() }
    }

    /// Drop every pending timer without firing it.
    public static func reset() {
        entries.removeAll()
    }

    fileprivate static func schedule(_ seconds: Double, _ body: @escaping @MainActor () -> Void) -> UInt64 {
        let id = nextID
        nextID += 1
        entries.append(Entry(id: id, remaining: seconds, body: body))
        return id
    }

    fileprivate static func cancel(_ id: UInt64) {
        entries.removeAll { $0.id == id }
    }
}

#endif
