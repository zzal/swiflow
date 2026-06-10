// Sources/SwiflowFetcher/HTTP.swift
//
// Static convenience facade over a base-URL-less `HTTPClient`, for one-off
// requests against absolute URLs. For a configured client (base URL + default
// headers), construct an `HTTPClient` directly. WASM-only, like `HTTPClient`.

#if canImport(JavaScriptKit)

/// One-off JSON requests against absolute URLs.
///
/// ```swift
/// let user = try await HTTP.get("https://api.example.com/me", as: User.self)
/// ```
///
/// This is a thin wrapper over `HTTPClient()` (no base URL). When you make more
/// than a couple of calls to the same host, prefer constructing an
/// `HTTPClient(baseURL:headers:)` and calling it with relative paths.
public enum HTTP {
    public static func get<T: Decodable & Sendable>(
        _ url: String, headers: [String: String] = [:], as type: T.Type = T.self
    ) async throws -> T {
        try await HTTPClient().get(url, headers: headers, as: type)
    }

    public static func post<T: Decodable & Sendable>(
        _ url: String, json: JSONValue, headers: [String: String] = [:], as type: T.Type = T.self
    ) async throws -> T {
        try await HTTPClient().post(url, json: json, headers: headers, as: type)
    }

    public static func put<T: Decodable & Sendable>(
        _ url: String, json: JSONValue, headers: [String: String] = [:], as type: T.Type = T.self
    ) async throws -> T {
        try await HTTPClient().put(url, json: json, headers: headers, as: type)
    }

    public static func patch<T: Decodable & Sendable>(
        _ url: String, json: JSONValue, headers: [String: String] = [:], as type: T.Type = T.self
    ) async throws -> T {
        try await HTTPClient().patch(url, json: json, headers: headers, as: type)
    }

    public static func delete(_ url: String, headers: [String: String] = [:]) async throws {
        try await HTTPClient().delete(url, headers: headers)
    }
}

#endif
