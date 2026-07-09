// Sources/SwiflowFetcher/HTTPClient.swift
//
// A configured JSON HTTP client: a base URL + default headers applied to every
// request, sent through an injected `HTTPTransport` (browser default:
// `FetchTransport`). The client itself is pure Swift and host-testable —
// request building, header merge, status mapping, and decode policy all run
// on every platform; only the transport touches JavaScriptKit.

import Swiflow
#if arch(wasm32)
import JavaScriptKit
#else
import Foundation // host-only: !arch(wasm32)-gated, never compiled into the wasm binary
#endif

/// A reusable HTTP client bound to a base URL and default headers — construct
/// once, call with relative paths.
///
/// ```swift
/// let api = HTTPClient(baseURL: "https://api.example.com", headers: ["Authorization": token])
/// let todos = try await api.get("/todos", as: [Todo].self)
/// let hits  = try await api.get("/search", query: ["name": .string(q), "count": 5], as: [Todo].self)
/// let made  = try await api.post("/todos", json: ["title": .string(title)], as: Todo.self)
/// let saved = try await api.put("/todos/\(id)", body: todo, as: Todo.self)   // todo: Encodable
/// try await api.delete("/todos/\(id)")
/// ```
///
/// `query:` parameters are percent-encoded and appended for you (keys sorted,
/// so the same parameters always produce the same URL) — never interpolate
/// user input into the path by hand.
///
/// For one-off requests against absolute URLs, the static `HTTP` facade wraps a
/// base-URL-less client. Tests inject a mock `HTTPTransport` (the same seam
/// `QueryClient` uses for its clock).
///
/// **Concurrency:** `Sendable`, and every method is `nonisolated`, taking
/// `Sendable` inputs and returning a `Sendable` result, so a `@MainActor`
/// `Query.fetch()` / `Mutation.perform()` can `await` these without crossing
/// an actor boundary. `Swiflow.render(...)` installs the JS event-loop
/// executor, so no setup is required in the browser.
///
/// **Decoding:** responses decode from the body text — with JavaScriptKit's
/// `JSValueDecoder` in the browser (`Foundation`/`JSONDecoder` aren't
/// available under WASM) and `JSONDecoder` on the host — so result types are
/// `Decodable & Sendable`. Bodies are sent as `JSONValue`.
public struct HTTPClient: Sendable {
    /// Prepended to relative request paths. Empty for the `HTTP` facade.
    public let baseURL: String
    /// Sent on every request; a per-call header of the same name overrides.
    public let defaultHeaders: [String: String]
    /// Performs the exchanges. Injected for tests; `FetchTransport` in the browser.
    let transport: any HTTPTransport

    /// Explicit-transport initializer — the injection seam, available on
    /// every platform.
    public init(baseURL: String = "", headers: [String: String] = [:], transport: any HTTPTransport) {
        self.baseURL = baseURL
        self.defaultHeaders = headers
        self.transport = transport
    }

    #if canImport(JavaScriptKit)
    /// Browser initializer — defaults to the `fetch`-backed transport.
    /// (JavaScriptKit compiles on the host too, so this exists there as well;
    /// like the pre-seam client, actually SENDING through `FetchTransport`
    /// requires a real JS runtime. Host tests inject a mock transport.)
    public init(baseURL: String = "", headers: [String: String] = [:]) {
        self.init(baseURL: baseURL, headers: headers, transport: FetchTransport())
    }
    #endif

    // MARK: - Verbs

    public func get<T: Decodable & Sendable>(
        _ path: String, query: [String: HTTPQueryValue] = [:],
        headers: [String: String] = [:], as _: T.Type = T.self
    ) async throws -> T {
        try decode(try await send(.get, path, query: query, body: nil, headers: headers))
    }

    public func post<T: Decodable & Sendable>(
        _ path: String, json: JSONValue, query: [String: HTTPQueryValue] = [:],
        headers: [String: String] = [:], as _: T.Type = T.self
    ) async throws -> T {
        try decode(try await send(.post, path, query: query, body: json, headers: headers))
    }

    /// POST an `Encodable` value as the JSON body — the typed counterpart of
    /// `json:`, encoded through `JSONValueEncoder` (the same Codable behavior
    /// on every platform: `encodeIfPresent` omits nil fields, etc.). A body
    /// whose own `encode(to:)` throws rethrows that error unchanged, before
    /// any request is sent.
    public func post<T: Decodable & Sendable>(
        _ path: String, body: some Encodable & Sendable, query: [String: HTTPQueryValue] = [:],
        headers: [String: String] = [:], as _: T.Type = T.self
    ) async throws -> T {
        try decode(try await send(.post, path, query: query, body: JSONValueEncoder().encode(body), headers: headers))
    }

    public func put<T: Decodable & Sendable>(
        _ path: String, json: JSONValue, query: [String: HTTPQueryValue] = [:],
        headers: [String: String] = [:], as _: T.Type = T.self
    ) async throws -> T {
        try decode(try await send(.put, path, query: query, body: json, headers: headers))
    }

    /// PUT an `Encodable` value as the JSON body. See `post(_:body:)`.
    public func put<T: Decodable & Sendable>(
        _ path: String, body: some Encodable & Sendable, query: [String: HTTPQueryValue] = [:],
        headers: [String: String] = [:], as _: T.Type = T.self
    ) async throws -> T {
        try decode(try await send(.put, path, query: query, body: JSONValueEncoder().encode(body), headers: headers))
    }

    public func patch<T: Decodable & Sendable>(
        _ path: String, json: JSONValue, query: [String: HTTPQueryValue] = [:],
        headers: [String: String] = [:], as _: T.Type = T.self
    ) async throws -> T {
        try decode(try await send(.patch, path, query: query, body: json, headers: headers))
    }

    /// PATCH an `Encodable` value as the JSON body. See `post(_:body:)`.
    public func patch<T: Decodable & Sendable>(
        _ path: String, body: some Encodable & Sendable, query: [String: HTTPQueryValue] = [:],
        headers: [String: String] = [:], as _: T.Type = T.self
    ) async throws -> T {
        try decode(try await send(.patch, path, query: query, body: JSONValueEncoder().encode(body), headers: headers))
    }

    /// Fire-and-forget DELETE — the response body (if any) is discarded, so a
    /// `204 No Content` is handled without a decode.
    public func delete(
        _ path: String, query: [String: HTTPQueryValue] = [:], headers: [String: String] = [:]
    ) async throws {
        _ = try await send(.delete, path, query: query, body: nil, headers: headers)
    }

    // MARK: - Core

    private enum Method: String { case get = "GET", post = "POST", put = "PUT", patch = "PATCH", delete = "DELETE" }

    /// Joins `baseURL` and `path`. An absolute `path` (http/https) is used
    /// as-is so the `HTTP` facade can pass full URLs through a base-URL-less client.
    private func resolve(_ path: String) -> String {
        if baseURL.isEmpty { return path }
        if path.hasPrefix("http://") || path.hasPrefix("https://") { return path }
        let base = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        let suffix = path.hasPrefix("/") ? path : "/" + path
        return base + suffix
    }

    /// Appends the percent-encoded `query` parameters to a resolved URL,
    /// joining with `?` — or `&` when the path already carries a query string,
    /// so hand-written and typed parameters compose.
    private func appendQuery(to url: String, query: [String: HTTPQueryValue]) -> String {
        guard !query.isEmpty else { return url }
        return url + (url.contains("?") ? "&" : "?") + QueryStringEncoding.queryString(query)
    }

    /// Builds the final request (resolved URL + encoded query, merged headers,
    /// serialized body), performs it through the transport, and maps a non-2xx
    /// status to `HTTPError.status` carrying the transport's best-effort body capture.
    private func send(_ method: Method, _ path: String, query: [String: HTTPQueryValue], body: JSONValue?, headers: [String: String]) async throws -> HTTPResponse {
        var merged = defaultHeaders.merging(headers, uniquingKeysWith: { _, perCall in perCall })
        var bodyString: String? = nil
        if let body {
            // Deliberately AFTER the merge: a JSON body always ships as JSON,
            // even if a default or per-call header said otherwise.
            merged["Content-Type"] = "application/json"
            bodyString = body.jsonString
        }
        let request = HTTPRequest(method: method.rawValue, url: appendQuery(to: resolve(path), query: query), headers: merged, body: bodyString)
        let response = try await transport.send(request)
        guard response.ok else {
            throw HTTPError.status(response.status, body: response.body)
        }
        return response
    }

    /// Decodes a successful response's JSON body into `T`. An unreadable or
    /// unparseable body is a `.transport` error (the exchange never produced
    /// usable JSON — the same bucket a rejected `response.json()` fell into);
    /// a parseable-but-mismatched body is a `.decoding` error.
    private func decode<T: Decodable & Sendable>(_ response: HTTPResponse) throws -> T {
        guard let text = response.body else {
            throw HTTPError.transport("response body could not be read")
        }
        #if arch(wasm32)
        guard let parse = JSObject.global.JSON.object?.parse.function else {
            throw HTTPError.transport("JSON.parse is unavailable")
        }
        // `JSON.parse` throws on malformed input — call it as a throwing JS
        // function (same idiom as PersistentStore) so a non-JSON body surfaces
        // as `.transport` rather than trapping the wasm.
        let json: JSValue
        do { json = try parse.throws(text) }
        catch { throw HTTPError.transport("response body was not valid JSON: \(String(describing: error))") }
        do { return try JSValueDecoder().decode(T.self, from: json) }
        catch { throw HTTPError.decoding(String(describing: error)) }
        #else
        do { return try JSONDecoder().decode(T.self, from: Data(text.utf8)) }
        catch let error as DecodingError {
            switch error {
            case .dataCorrupted:
                // JSONDecoder folds "not JSON at all" into DecodingError;
                // keep the wasm split: parse-level failures are transport.
                throw HTTPError.transport("response body was not valid JSON: \(String(describing: error))")
            default:
                throw HTTPError.decoding(String(describing: error))
            }
        }
        catch { throw HTTPError.decoding(String(describing: error)) }
        #endif
    }
}
