// Sources/SwiflowWeb/BackgroundRevalidation.swift
#if canImport(JavaScriptKit)
import JavaScriptKit
import SwiflowQuery

/// Installs the production background-revalidation triggers for one render root:
/// a ~1s `setInterval` driving `queryClient.tick(now:)`, and a `visibilitychange`
/// + window `focus` listener driving `queryClient.focusChanged(visible:)`.
///
/// Retains its `JSClosure`s for their lifetime (JavaScriptKit ref-counts them);
/// `stop()` releases them and tears down the JS handles, mirroring `RAFScheduler`.
@MainActor
final class BackgroundRevalidation {
    private weak var client: QueryClient?
    private let clock: any QueryClock
    private var intervalID: JSValue?
    private var tickClosure: JSClosure?
    private var focusClosure: JSClosure?

    init(client: QueryClient, clock: any QueryClock) {
        self.client = client
        self.clock = clock
    }

    func start() {
        let tick = JSClosure { [weak self] _ -> JSValue in
            guard let self, let client = self.client else { return .undefined }
            client.tick(now: self.clock.now())
            return .undefined
        }
        tickClosure = tick
        intervalID = JSObject.global.setInterval!(JSValue.object(tick), 1000)

        let onFocus = JSClosure { [weak self] _ -> JSValue in
            self?.client?.focusChanged(visible: true)
            return .undefined
        }
        focusClosure = onFocus
        if let doc = JSObject.global.document.object {
            _ = doc.addEventListener!("visibilitychange", JSValue.object(onFocus))
        }
        _ = JSObject.global.addEventListener!("focus", JSValue.object(onFocus))
    }

    func stop() {
        if let id = intervalID { _ = JSObject.global.clearInterval!(id); intervalID = nil }
        if let onFocus = focusClosure {
            if let doc = JSObject.global.document.object {
                _ = doc.removeEventListener!("visibilitychange", JSValue.object(onFocus))
            }
            _ = JSObject.global.removeEventListener!("focus", JSValue.object(onFocus))
        }
        tickClosure = nil
        focusClosure = nil
    }
}
#endif
