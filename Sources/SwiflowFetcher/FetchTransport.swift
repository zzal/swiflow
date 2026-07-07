// Sources/SwiflowFetcher/FetchTransport.swift
//
// The browser transport: performs an `HTTPRequest` with `fetch`. WASM-only —
// the sole remaining JavaScriptKit crossing in the fetcher; everything above
// it (request building, header merge, status mapping, decode policy) lives in
// host-testable `HTTPClient`.

#if canImport(JavaScriptKit)
import JavaScriptKit
import JavaScriptEventLoop

/// `fetch`-backed `HTTPTransport`. The default transport for `HTTPClient` in
/// the browser.
///
/// **Cancellation:** each request carries an `AbortController` signal, and
/// cancelling the surrounding Swift task aborts the underlying `fetch` — so a
/// superseded request (an invalidated query, an optimistic write over an
/// in-flight fetch, typeahead churn) stops downloading instead of running to
/// completion. The cache's generation guards already made supersede *correct*;
/// this makes it *cheap*. An aborted exchange surfaces as `CancellationError`,
/// never as `HTTPError.transport`, so retry logic can't mistake a deliberate
/// cancel for a network failure.
///
/// **Concurrency:** stateless and `Sendable`; the non-`Sendable` JavaScriptKit
/// values are created and awaited internally under WASM's single-threaded
/// executor (same stance as the rest of Swiflow's JS code).
public struct FetchTransport: HTTPTransport {
    public init() {}

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        // A task cancelled before we start shouldn't fire a doomed request.
        try Task.checkCancellation()

        let options = JSObject.global.Object.function!.new()
        options.method = .string(request.method)

        let headerObject = JSObject.global.Object.function!.new()
        for (name, value) in request.headers {
            headerObject[name] = .string(value)
        }
        options.headers = .object(headerObject)
        if let body = request.body {
            options.body = .string(body)
        }

        // Wire the abort signal (graceful on an embedder without
        // AbortController: the request simply isn't cancellable mid-flight).
        var abortBox: AbortControllerBox?
        if let controllerConstructor = JSObject.global.AbortController.function {
            let controller = controllerConstructor.new()
            options.signal = controller.signal
            abortBox = AbortControllerBox(controller: controller)
        }

        guard let promiseValue = JSObject.global.fetch.function?(request.url, JSValue.object(options)).object,
              let promise = JSPromise(promiseValue) else {
            throw HTTPError.transport("fetch did not return a Promise")
        }
        let response: JSValue
        do {
            response = try await withTaskCancellationHandler {
                try await promise.value
            } onCancel: { [abortBox] in
                // The handler runs synchronously wherever cancel() was called;
                // JS objects may only be touched on the JS thread, so hop to
                // the main actor (under WASM's single-threaded executor this
                // is the same thread — the hop satisfies isolation, and the
                // rejected promise above unblocks the await). Aborting an
                // already-settled fetch is a spec-level no-op, so a late
                // cancel is harmless.
                guard let abortBox else { return }
                Task { @MainActor in abortBox.abort() }
            }
        } catch {
            // An abort rejects the promise with an AbortError — surface the
            // task's cancellation as Swift cancellation, not as a fake
            // network failure a retry policy would chase.
            if Task.isCancelled { throw CancellationError() }
            throw HTTPError.transport(String(describing: error))
        }

        let body = await Self.readBody(response)
        // The signal also aborts an in-progress body read (readBody swallows
        // that to `nil`) — convert a cancel-during-read into cancellation
        // rather than letting a nil body masquerade as a transport problem.
        try Task.checkCancellation()
        return HTTPResponse(
            status: Int(response.status.number ?? 0),
            body: body)
    }

    /// Carries the JS `AbortController` across the `@Sendable` cancellation
    /// handler into a main-actor hop. `@unchecked Sendable` is safe for the
    /// same reason as PersistentStore's `DatabaseBox`: it's a JS-heap
    /// reference, and everything runs on WASM's single JS thread — the box
    /// only exists to satisfy `Sendable` checking on the closure boundary.
    private struct AbortControllerBox: @unchecked Sendable {
        let controller: JSObject
        @MainActor func abort() { _ = controller.abort?() }
    }

    /// Best-effort read of the response text. Swallows any failure (already
    /// consumed body, malformed `text()` result, rejected promise) and returns
    /// `nil` — the client decides what a missing body means per status, so a
    /// body-read problem can never mask the original status error.
    private static func readBody(_ response: JSValue) async -> String? {
        guard let textValue = response.text().object, let textPromise = JSPromise(textValue) else {
            return nil
        }
        guard let text = try? await textPromise.value else { return nil }
        return text.string
    }
}

#endif
