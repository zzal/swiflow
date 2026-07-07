// Sources/SwiflowFetcher/Transport.swift
//
// The transport seam: plain-Swift request/response values and the protocol
// `HTTPClient` sends them through. Pure Swift (no JavaScriptKit) so the
// client's request-building, header-merge, and error-mapping logic is
// host-testable with a mock transport — the same injection seam QueryClient
// uses for its clock. The browser implementation is `FetchTransport`.

/// One fully-prepared HTTP exchange, as handed to a transport: the URL is
/// already resolved against the client's base, the headers already merged
/// (defaults ← per-call ← Content-Type), and the body already serialized.
public struct HTTPRequest: Sendable, Equatable {
    /// The HTTP method, uppercase ("GET", "POST", …).
    public let method: String
    /// The fully-resolved absolute or site-relative URL.
    public let url: String
    /// The final header set — nothing is added downstream.
    public let headers: [String: String]
    /// The serialized JSON body, or `nil` for body-less requests.
    public let body: String?

    public init(method: String, url: String, headers: [String: String], body: String?) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }
}

/// What a transport got back. The body is read eagerly, best-effort: `nil`
/// means it couldn't be read (already consumed, network hiccup mid-read) —
/// never a thrown error, so a body-read problem can't mask a status error.
public struct HTTPResponse: Sendable, Equatable {
    /// The HTTP status code.
    public let status: Int
    /// The raw response text, or `nil` if unreadable.
    public let body: String?

    /// Mirrors `Response.ok` from the fetch spec: status in 200–299.
    public var ok: Bool { (200..<300).contains(status) }

    public init(status: Int, body: String?) {
        self.status = status
        self.body = body
    }
}

/// Performs HTTP exchanges for `HTTPClient`. Implementations throw
/// `HTTPError.transport` for network-level failures (the request never
/// produced a usable response) and return responses of ANY status — mapping
/// non-2xx to `HTTPError.status` is the client's job, so the policy is
/// host-tested once, not re-implemented per transport.
///
/// This seam is also where request cancellation will live (audit II Wave-2
/// #4): a transport that wires an `AbortController` can abort the underlying
/// fetch when the surrounding Swift task is cancelled.
public protocol HTTPTransport: Sendable {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}
