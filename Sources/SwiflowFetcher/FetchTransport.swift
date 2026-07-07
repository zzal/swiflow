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
/// **Concurrency:** stateless and `Sendable`; the non-`Sendable` JavaScriptKit
/// values are created and awaited internally under WASM's single-threaded
/// executor (same stance as the rest of Swiflow's JS code).
public struct FetchTransport: HTTPTransport {
    public init() {}

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
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

        guard let promiseValue = JSObject.global.fetch.function?(request.url, JSValue.object(options)).object,
              let promise = JSPromise(promiseValue) else {
            throw HTTPError.transport("fetch did not return a Promise")
        }
        let response: JSValue
        do { response = try await promise.value }
        catch { throw HTTPError.transport(String(describing: error)) }

        return HTTPResponse(
            status: Int(response.status.number ?? 0),
            body: await Self.readBody(response))
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
