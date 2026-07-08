// Sources/SwiflowRouter/Web/BrowserNavigator.swift
#if canImport(JavaScriptKit)
import JavaScriptKit
import Swiflow

/// The production `Navigator`, backed by `window.location`, `window.history`,
/// and window event listeners. A verbatim move of the JS calls RouterRoot
/// used to open-code — mode logic stays in RouterRoot; this class is only
/// the crossing.
///
/// Globals resolve per call through the guarded accessors below, which trap
/// with a NAMED cause when the browser surface is missing (the JSDriver
/// precedent: `fatalError`, not `swiflowDiagnostic`, so the message survives
/// release builds — a router without `window`/`history` is a dead app in
/// every configuration, this just makes the crash say why).
@MainActor
package final class BrowserNavigator: Navigator {
    /// Held for ownership clarity (mirrors `RAFScheduler.rafClosure`), not
    /// because it's what keeps the listener callable — `JSClosure.init`
    /// self-registers into JavaScriptKit's static `sharedClosures` table.
    /// What actually stops it from firing is `stopListening`'s explicit
    /// `removeEventListener` call.
    private var listenerClosure: JSClosure?
    /// The exact `JSValue` registered as the listener in `startListening`,
    /// stored so `stopListening`'s `removeEventListener` passes the SAME
    /// reference `addEventListener` got (mirrors
    /// `BackgroundRevalidation.focusListener`).
    private var listenerValue: JSValue?
    /// The event name registered alongside `listenerValue`.
    private var listenerEvent: String?

    package init() {}

    private var window: JSObject {
        guard let w = JSObject.global.window.object else {
            fatalError(
                "Swiflow router: `window` is unavailable. The router requires "
                    + "a browser environment; host tests must inject a Navigator."
            )
        }
        return w
    }

    private var history: JSObject {
        guard let h = JSObject.global.history.object else {
            fatalError(
                "Swiflow router: the browser `history` API is unavailable. The "
                    + "router requires a browser environment; host tests must "
                    + "inject a Navigator."
            )
        }
        return h
    }

    private var location: JSObject {
        guard let l = window["location"].object else {
            fatalError(
                "Swiflow router: `window.location` is unavailable. The router "
                    + "requires a browser environment; host tests must inject a "
                    + "Navigator."
            )
        }
        return l
    }

    package var hash: String { location["hash"].string ?? "" }
    package var pathname: String { location["pathname"].string ?? "/" }
    package var search: String { location["search"].string ?? "" }

    package func setHash(_ path: String) {
        location["hash"] = path.jsValue
    }

    package func pushState(_ url: String) {
        _ = history.pushState!(JSValue.null, "".jsValue, url.jsValue)
    }

    package func replaceState(_ url: String) {
        _ = history.replaceState!(JSValue.null, "".jsValue, url.jsValue)
    }

    package func back() {
        _ = history.back!()
    }

    package func startListening(to event: String, handler: @escaping @MainActor () -> Void) {
        stopListening() // single-listener contract: replace any prior registration
        let closure = JSClosure { _ -> JSValue in
            handler()
            return .undefined
        }
        let value = JSValue.object(closure)
        _ = window.addEventListener!(event.jsValue, value)
        listenerClosure = closure
        listenerValue = value
        listenerEvent = event
    }

    package func stopListening() {
        if let event = listenerEvent, let value = listenerValue {
            _ = window.removeEventListener!(event.jsValue, value)
        }
        // Nil the closure AFTER removeEventListener, so the JSClosure stays
        // alive through the remove (mirrors `BackgroundRevalidation.stop()`).
        listenerClosure = nil
        listenerValue = nil
        listenerEvent = nil
    }
}
#endif
