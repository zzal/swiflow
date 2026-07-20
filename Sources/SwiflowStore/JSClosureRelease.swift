// Sources/SwiflowStore/JSClosureRelease.swift
#if arch(wasm32)
import JavaScriptKit

extension JSClosure {
    /// Release this closure's entry from JavaScriptKit's static closure table
    /// — but ONLY under `-DJAVASCRIPTKIT_WITHOUT_WEAKREFS`, the legacy build
    /// for browsers without WeakRefs, where it is REQUIRED (`JSClosure`'s
    /// `deinit` `fatalError`s if the closure is deallocated unreleased).
    ///
    /// On the default (WeakRefs) build `JSClosure.release()` is a deprecated
    /// no-op: cleanup runs when the underlying JS function is garbage-collected
    /// via a `FinalizationRegistry` callback. That collection can only happen
    /// once the closure is both detached from JS (`removeEventListener` /
    /// `clearInterval`) AND no longer referenced from Swift — which is why
    /// every caller does the detach before dropping its field. Calling this
    /// keeps the legacy build correct without emitting the deprecation warning
    /// on the default build.
    func releaseIfNeeded() {
        #if JAVASCRIPTKIT_WITHOUT_WEAKREFS
        release()
        #endif
    }
}
#endif
