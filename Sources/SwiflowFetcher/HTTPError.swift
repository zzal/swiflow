// Sources/SwiflowFetcher/HTTPError.swift
//
// Public error type for `HTTP`. Pure Swift (no JavaScriptKit) so it's part of
// the module's API on every platform, not just WASM.

/// An error from an `HTTP` request.
public enum HTTPError: Error, Sendable, CustomStringConvertible, Equatable {
    /// The server responded with a non-2xx status code. `body` is a
    /// best-effort capture of the response text (e.g. a JSON error payload
    /// or plain-text message) — `nil` if the body couldn't be read (already
    /// consumed, network hiccup mid-read, etc.), never a thrown error on its
    /// own.
    case status(Int, body: String?)
    /// The request never produced a usable response — a network failure, a
    /// rejected `fetch` promise, or a malformed fetch result. The associated
    /// string is a short diagnostic.
    case transport(String)
    /// The response body could not be decoded into the requested type. The
    /// associated string is the underlying decoding error's description.
    case decoding(String)

    public var description: String {
        switch self {
        case .status(let code, let body):
            guard let body, !body.isEmpty else { return "HTTP \(code)" }
            return "HTTP \(code): \(body)"
        case .transport(let why): return "Transport error: \(why)"
        case .decoding(let why):  return "Decoding error: \(why)"
        }
    }
}
