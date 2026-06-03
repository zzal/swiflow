import JavaScriptKit
import JavaScriptEventLoop

/// Errors surfaced by the example's tiny fetch helper. Kept local to the
/// example; this is the candidate that may later graduate into a `SwiflowHTTP`
/// framework module if it proves its worth.
enum HTTPError: Error, CustomStringConvertible {
    case notOK(Int)
    case badResponse        // fetch / .json() did not return the expected JS shape
    case decode(String)     // JSValueDecoder threw

    var description: String {
        switch self {
        case .notOK(let s):    return "HTTP \(s)"
        case .badResponse:     return "Malformed response"
        case .decode(let why): return "Decode failed: \(why)"
        }
    }
}

enum HTTPMethod: String { case GET, POST, PUT, DELETE }

/// One field of a JSON request body. A `Sendable` value type so a body can
/// cross into `Net`'s nonisolated async context without smuggling a
/// non-`Sendable` `JSObject` across an actor boundary.
enum JSONField: Sendable {
    case string(String)
    case bool(Bool)
    case int(Int)
}

/// Minimal JSON-over-`fetch` helper for the browser/WASM target.
///
/// **Nonisolated by design:** it takes `Sendable` inputs (`String`,
/// `[String: JSONField]`) and returns `Sendable` results, building and awaiting
/// every non-`Sendable` JavaScriptKit value (`JSObject`, `JSPromise`, `JSValue`)
/// *internally*. That lets `@MainActor` `Query.fetch()` / `Mutation.perform()`
/// `await` it without sending a non-`Sendable` value across the actor boundary —
/// and without forcing `JSPromise.value` (nonisolated) to exit the main actor.
///
/// No `Foundation`/`JSONDecoder` and no `JSValueEncoder`: request bodies are
/// built as JS objects + `JSON.stringify`, responses decoded with
/// `JSValueDecoder`. Async works because `Swiflow.render(...)` installs the JS
/// event-loop executor.
enum Net {
    /// Build a `fetch` init object: `{ method, headers?, body? }` from a
    /// `Sendable` field map.
    private static func makeInit(_ method: HTTPMethod, _ fields: [String: JSONField]?) -> JSValue {
        let o = JSObject.global.Object.function!.new()
        o.method = .string(method.rawValue)
        if let fields {
            let h = JSObject.global.Object.function!.new()
            h["Content-Type"] = .string("application/json")
            o.headers = .object(h)
            let bodyObj = JSObject.global.Object.function!.new()
            for (key, value) in fields {
                switch value {
                case .string(let s): bodyObj[key] = .string(s)
                case .bool(let b):   bodyObj[key] = .boolean(b)
                case .int(let i):    bodyObj[key] = .number(Double(i))
                }
            }
            o.body = JSObject.global.JSON.object!.stringify!(bodyObj)
        }
        return .object(o)
    }

    /// Await a `fetch` and assert `response.ok` (fetch resolves on 4xx/5xx).
    private static func fetchOK(_ url: String, _ initVal: JSValue) async throws -> JSValue {
        guard let p = JSObject.global.fetch.function!(url, initVal).object,
              let promise = JSPromise(p) else { throw HTTPError.badResponse }
        let resp = try await promise.value
        guard resp.ok.boolean == true else { throw HTTPError.notOK(Int(resp.status.number ?? 0)) }
        return resp
    }

    /// Decode the JSON body of a Response `JSValue` into `T`.
    private static func decodeJSON<T: Decodable>(_ resp: JSValue, as _: T.Type) async throws -> T {
        guard let j = resp.json().object, let jp = JSPromise(j) else { throw HTTPError.badResponse }
        let json = try await jp.value
        do { return try JSValueDecoder().decode(T.self, from: json) }
        catch { throw HTTPError.decode(String(describing: error)) }
    }

    /// GET → decoded `T`.
    static func get<T: Decodable & Sendable>(_ url: String, as type: T.Type = T.self) async throws -> T {
        try await decodeJSON(fetchOK(url, makeInit(.GET, nil)), as: type)
    }

    /// POST/PUT with a JSON body → decoded `T`.
    static func send<T: Decodable & Sendable>(
        _ method: HTTPMethod, _ url: String, json fields: [String: JSONField], as type: T.Type = T.self
    ) async throws -> T {
        try await decodeJSON(fetchOK(url, makeInit(method, fields)), as: type)
    }

    /// DELETE / fire-and-forget — no body decode (handles empty 204 responses).
    static func send(_ method: HTTPMethod, _ url: String, json fields: [String: JSONField]? = nil) async throws {
        _ = try await fetchOK(url, makeInit(method, fields))
    }
}
