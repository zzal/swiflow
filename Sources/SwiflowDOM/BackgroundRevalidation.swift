// Sources/SwiflowDOM/BackgroundRevalidation.swift
#if canImport(JavaScriptKit)
import JavaScriptKit
import SwiflowQuery

/// Installs the production background-revalidation triggers for one render root:
/// a ~1s `setInterval` driving `queryClient.tick(now:)`, and a `visibilitychange`
/// + window `focus` listener driving `queryClient.focusChanged(visible:)`.
///
/// Holds its `JSClosure`s for ownership clarity, mirroring `RAFScheduler` —
/// not because that's what keeps them callable (`JSClosure.init`
/// self-registers into JavaScriptKit's static `sharedClosures` table). What
/// actually stops them from firing is `stop()`'s explicit `clearInterval` /
/// `removeEventListener` calls, which is why it nils the fields only AFTER
/// those calls run (see comment below).
@MainActor
final class BackgroundRevalidation {
    private weak var client: QueryClient?
    private let clock: any QueryClock
    private var intervalID: JSValue?
    private var tickClosure: JSClosure?
    private var focusClosure: JSClosure?
    /// The exact `JSValue` registered as the focus/visibility listener, stored so
    /// `removeEventListener` passes the SAME reference that `addEventListener` got.
    private var focusListener: JSValue?

    init(client: QueryClient, clock: any QueryClock) {
        self.client = client
        self.clock = clock
    }

    func start() {
        guard tickClosure == nil else { return }   // idempotent: never double-install

        let tick = JSClosure { [weak self] _ -> JSValue in
            guard let self, let client = self.client else { return .undefined }
            client.tick(now: self.clock.now())
            return .undefined
        }
        tickClosure = tick
        intervalID = JSObject.global.setInterval!(JSValue.object(tick), 1000)

        // Shared by `visibilitychange` and window `focus`. Reads the actual
        // visibility state, so a tab HIDE (`visibilitychange` → "hidden") passes
        // `visible: false` (a no-op in focusChanged) instead of refetching.
        let onFocus = JSClosure { [weak self] _ -> JSValue in
            guard let self, let client = self.client else { return .undefined }
            var visible = true
            if let doc = JSObject.global.document.object {
                visible = doc.visibilityState.string == "visible"
            }
            client.focusChanged(visible: visible)
            return .undefined
        }
        focusClosure = onFocus
        let listener = JSValue.object(onFocus)
        focusListener = listener
        if let doc = JSObject.global.document.object {
            _ = doc.addEventListener!("visibilitychange", listener)
        }
        _ = JSObject.global.addEventListener!("focus", listener)
    }

    func stop() {
        if let id = intervalID { _ = JSObject.global.clearInterval!(id); intervalID = nil }
        if let listener = focusListener {
            if let doc = JSObject.global.document.object {
                _ = doc.removeEventListener!("visibilitychange", listener)
            }
            _ = JSObject.global.removeEventListener!("focus", listener)
        }
        // Release AFTER the removeEventListener calls (removal stops the
        // callbacks; release() drops their pinned `sharedClosures` entries —
        // nil-ing the fields alone leaks them in that static table).
        focusListener = nil
        tickClosure?.release()
        tickClosure = nil
        focusClosure?.release()
        focusClosure = nil
    }
}
#endif
