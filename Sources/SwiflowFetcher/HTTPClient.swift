// Sources/SwiflowFetcher/HTTPClient.swift
//
// A configured JSON-over-`fetch` client: a base URL + default headers applied
// to every request. WASM-only (behind `#if canImport(JavaScriptKit)`), like
// the rest of Swiflow's JS code.

#if canImport(JavaScriptKit)
import JavaScriptKit
import JavaScriptEventLoop

/// A reusable HTTP client bound to a base URL and default headers — construct
/// once, call with relative paths.
///
/// ```swift
/// let api = HTTPClient(baseURL: "https://api.example.com", headers: ["Authorization": token])
/// let todos = try await api.get("/todos", as: [Todo].self)
/// let made  = try await api.post("/todos", json: ["title": .string(title)], as: Todo.self)
/// try await api.delete("/todos/\(id)")
/// ```
///
/// For one-off requests against absolute URLs, the static `HTTP` facade wraps a
/// base-URL-less client.
///
/// **Concurrency:** `Sendable` (a value of `String` + `[String: String]`), and
/// every method is `nonisolated`, taking `Sendable` inputs and returning a
/// `Sendable` result. All non-`Sendable` JavaScriptKit values are created and
/// awaited internally, so a `@MainActor` `Query.fetch()` / `Mutation.perform()`
/// can `await` these without crossing an actor boundary. `Swiflow.render(...)`
/// installs the JS event-loop executor, so no setup is required.
///
/// **Decoding:** responses decode with JavaScriptKit's `JSValueDecoder`
/// (`Foundation`/`JSONDecoder` aren't available under WASM), so result types
/// are `Decodable & Sendable`. Bodies are sent as `JSONValue`.
public struct HTTPClient: Sendable {
    /// Prepended to relative request paths. Empty for the `HTTP` facade.
    public let baseURL: String
    /// Sent on every request; a per-call header of the same name overrides.
    public let defaultHeaders: [String: String]

    public init(baseURL: String = "", headers: [String: String] = [:]) {
        self.baseURL = baseURL
        self.defaultHeaders = headers
    }

    // MARK: - Verbs

    public func get<T: Decodable & Sendable>(
        _ path: String, headers: [String: String] = [:], as _: T.Type = T.self
    ) async throws -> T {
        try await decode(send(.get, path, body: nil, headers: headers))
    }

    public func post<T: Decodable & Sendable>(
        _ path: String, json: JSONValue, headers: [String: String] = [:], as _: T.Type = T.self
    ) async throws -> T {
        try await decode(send(.post, path, body: json, headers: headers))
    }

    public func put<T: Decodable & Sendable>(
        _ path: String, json: JSONValue, headers: [String: String] = [:], as _: T.Type = T.self
    ) async throws -> T {
        try await decode(send(.put, path, body: json, headers: headers))
    }

    public func patch<T: Decodable & Sendable>(
        _ path: String, json: JSONValue, headers: [String: String] = [:], as _: T.Type = T.self
    ) async throws -> T {
        try await decode(send(.patch, path, body: json, headers: headers))
    }

    /// Fire-and-forget DELETE — the response body (if any) is discarded, so a
    /// `204 No Content` is handled without a decode.
    public func delete(_ path: String, headers: [String: String] = [:]) async throws {
        _ = try await send(.delete, path, body: nil, headers: headers)
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

    /// Performs the request and returns the raw `Response` `JSValue` after
    /// asserting `response.ok`. Internal — `JSValue` never escapes to a caller.
    private func send(_ method: Method, _ path: String, body: JSONValue?, headers: [String: String]) async throws -> JSValue {
        let options = JSObject.global.Object.function!.new()
        options.method = .string(method.rawValue)

        let headerObject = JSObject.global.Object.function!.new()
        for (name, value) in defaultHeaders.merging(headers, uniquingKeysWith: { _, perCall in perCall }) {
            headerObject[name] = .string(value)
        }
        if let body {
            headerObject["Content-Type"] = .string("application/json")
            options.body = .string(body.jsonString)
        }
        options.headers = .object(headerObject)

        guard let promiseValue = JSObject.global.fetch.function?(resolve(path), JSValue.object(options)).object,
              let promise = JSPromise(promiseValue) else {
            throw HTTPError.transport("fetch did not return a Promise")
        }
        let response: JSValue
        do { response = try await promise.value }
        catch { throw HTTPError.transport(String(describing: error)) }

        guard response.ok.boolean == true else {
            throw HTTPError.status(Int(response.status.number ?? 0))
        }
        return response
    }

    /// Awaits and decodes a `Response`'s JSON body into `T`.
    private func decode<T: Decodable & Sendable>(_ response: JSValue) async throws -> T {
        guard let jsonValue = response.json().object, let jsonPromise = JSPromise(jsonValue) else {
            throw HTTPError.transport("response.json() did not return a Promise")
        }
        let json: JSValue
        do { json = try await jsonPromise.value }
        catch { throw HTTPError.transport(String(describing: error)) }

        do { return try JSValueDecoder().decode(T.self, from: json) }
        catch { throw HTTPError.decoding(String(describing: error)) }
    }
}

#endif
