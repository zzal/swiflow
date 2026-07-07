// Tests/SwiflowFetcherTests/HTTPClientTests.swift
//
// Host tests for HTTPClient's request-building, header-merge, status-mapping,
// and decode policy — through a mock HTTPTransport. Before the transport seam
// existed, ALL of this was #if-walled behind JavaScriptKit and only reachable
// by Playwright (audit II Wave-2 #3).
import Testing
import Swiflow
@testable import SwiflowFetcher

/// Scripted transport: records every request, answers from a closure.
/// `@unchecked Sendable`: each instance is test-local and accessed
/// sequentially (the test awaits every client call before inspecting), so no
/// concurrent access occurs.
private final class MockTransport: HTTPTransport, @unchecked Sendable {
    private(set) var requests: [HTTPRequest] = []
    private let respond: (HTTPRequest) throws -> HTTPResponse
    init(_ respond: @escaping (HTTPRequest) throws -> HTTPResponse) { self.respond = respond }
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        requests.append(request)
        return try respond(request)
    }

    static func returning(status: Int, body: String?) -> MockTransport {
        MockTransport { _ in HTTPResponse(status: status, body: body) }
    }
    var last: HTTPRequest? { requests.last }
}

private struct Item: Decodable, Equatable, Sendable { let id: Int; let name: String }

@Suite("HTTPClient/transport seam")
struct HTTPClientTests {

    // MARK: - URL resolution

    @Test("resolve joins base and path across slash variants; absolute paths pass through")
    func resolveJoinsBaseAndPath() async throws {
        let cases: [(base: String, path: String, expected: String)] = [
            ("http://api.test", "/todos", "http://api.test/todos"),
            ("http://api.test/", "/todos", "http://api.test/todos"),
            ("http://api.test", "todos", "http://api.test/todos"),
            ("http://api.test/", "todos", "http://api.test/todos"),
            ("http://api.test", "https://other.test/x", "https://other.test/x"),
            ("", "/relative", "/relative"),
        ]
        for c in cases {
            let mock = MockTransport.returning(status: 200, body: #"{"id":1,"name":"a"}"#)
            let client = HTTPClient(baseURL: c.base, transport: mock)
            _ = try await client.get("\(c.path)", as: Item.self)
            #expect(mock.last?.url == c.expected, "base=\(c.base) path=\(c.path)")
        }
    }

    // MARK: - Headers

    @Test("per-call headers override defaults; unrelated defaults survive")
    func perCallHeadersOverrideDefaults() async throws {
        let mock = MockTransport.returning(status: 200, body: #"{"id":1,"name":"a"}"#)
        let client = HTTPClient(
            baseURL: "http://api.test",
            headers: ["Authorization": "default-token", "X-App": "swiflow"],
            transport: mock)
        _ = try await client.get("/x", headers: ["Authorization": "per-call-token"], as: Item.self)
        #expect(mock.last?.headers["Authorization"] == "per-call-token")
        #expect(mock.last?.headers["X-App"] == "swiflow")
    }

    @Test("a JSON body forces Content-Type: application/json, even over a caller's header")
    func jsonBodyForcesContentType() async throws {
        let mock = MockTransport.returning(status: 200, body: #"{"id":1,"name":"a"}"#)
        let client = HTTPClient(baseURL: "http://api.test", transport: mock)
        _ = try await client.post("/x", json: ["k": .string("v")],
                                  headers: ["Content-Type": "text/plain"], as: Item.self)
        #expect(mock.last?.headers["Content-Type"] == "application/json")
    }

    @Test("a body-less request sets no Content-Type")
    func bodylessRequestSetsNoContentType() async throws {
        let mock = MockTransport.returning(status: 200, body: #"{"id":1,"name":"a"}"#)
        let client = HTTPClient(baseURL: "http://api.test", transport: mock)
        _ = try await client.get("/x", as: Item.self)
        #expect(mock.last?.headers["Content-Type"] == nil)
    }

    // MARK: - Verbs

    @Test("each verb sends its method; JSON verbs serialize the body, GET/DELETE send none")
    func verbsMapToMethodsAndBodies() async throws {
        let mock = MockTransport.returning(status: 200, body: #"{"id":1,"name":"a"}"#)
        let client = HTTPClient(baseURL: "http://api.test", transport: mock)

        _ = try await client.get("/x", as: Item.self)
        #expect(mock.last?.method == "GET")
        #expect(mock.last?.body == nil)

        _ = try await client.post("/x", json: ["title": .string("t")], as: Item.self)
        #expect(mock.last?.method == "POST")
        #expect(mock.last?.body == JSONValue.object(["title": .string("t")]).jsonString)

        _ = try await client.put("/x", json: ["done": .bool(true)], as: Item.self)
        #expect(mock.last?.method == "PUT")

        _ = try await client.patch("/x", json: ["n": .int(1)], as: Item.self)
        #expect(mock.last?.method == "PATCH")

        try await client.delete("/x")
        #expect(mock.last?.method == "DELETE")
        #expect(mock.last?.body == nil)
    }

    @Test("delete tolerates a 204 with no body (no decode attempted)")
    func deleteToleratesNoContent() async throws {
        let mock = MockTransport.returning(status: 204, body: nil)
        let client = HTTPClient(baseURL: "http://api.test", transport: mock)
        try await client.delete("/x")   // must not throw
    }

    // MARK: - Status mapping

    @Test("a non-2xx status throws HTTPError.status carrying the best-effort body")
    func non2xxThrowsStatusWithBody() async {
        let mock = MockTransport.returning(status: 404, body: #"{"error":"nope"}"#)
        let client = HTTPClient(baseURL: "http://api.test", transport: mock)
        do {
            _ = try await client.get("/missing", as: Item.self)
            Issue.record("expected HTTPError.status")
        } catch let error as HTTPError {
            #expect(error == .status(404, body: #"{"error":"nope"}"#))
        } catch { Issue.record("wrong error type: \(error)") }
    }

    @Test("an unreadable error body maps to HTTPError.status with body nil")
    func unreadableErrorBodyIsNil() async {
        let mock = MockTransport.returning(status: 500, body: nil)
        let client = HTTPClient(baseURL: "http://api.test", transport: mock)
        do {
            _ = try await client.get("/x", as: Item.self)
            Issue.record("expected HTTPError.status")
        } catch let error as HTTPError {
            #expect(error == .status(500, body: nil))
        } catch { Issue.record("wrong error type: \(error)") }
    }

    @Test("HTTPResponse.ok mirrors the fetch spec's 200–299 window")
    func okWindowMatchesFetchSpec() {
        #expect(!HTTPResponse(status: 199, body: nil).ok)
        #expect(HTTPResponse(status: 200, body: nil).ok)
        #expect(HTTPResponse(status: 299, body: nil).ok)
        #expect(!HTTPResponse(status: 300, body: nil).ok)
        #expect(!HTTPResponse(status: 404, body: nil).ok)
    }

    // MARK: - Decode policy

    @Test("a successful response decodes into the requested type")
    func successfulResponseDecodes() async throws {
        let mock = MockTransport.returning(status: 200, body: #"{"id":7,"name":"seven"}"#)
        let client = HTTPClient(baseURL: "http://api.test", transport: mock)
        let item = try await client.get("/x", as: Item.self)
        #expect(item == Item(id: 7, name: "seven"))
    }

    @Test("a non-JSON success body is a transport error (parse-level), not a decoding error")
    func nonJSONBodyIsTransportError() async {
        let mock = MockTransport.returning(status: 200, body: "<html>oops</html>")
        let client = HTTPClient(baseURL: "http://api.test", transport: mock)
        do {
            _ = try await client.get("/x", as: Item.self)
            Issue.record("expected HTTPError.transport")
        } catch let error as HTTPError {
            if case .transport = error {} else { Issue.record("expected .transport, got \(error)") }
        } catch { Issue.record("wrong error type: \(error)") }
    }

    @Test("a JSON body of the wrong shape is a decoding error")
    func wrongShapeIsDecodingError() async {
        let mock = MockTransport.returning(status: 200, body: #"{"unexpected":true}"#)
        let client = HTTPClient(baseURL: "http://api.test", transport: mock)
        do {
            _ = try await client.get("/x", as: Item.self)
            Issue.record("expected HTTPError.decoding")
        } catch let error as HTTPError {
            if case .decoding = error {} else { Issue.record("expected .decoding, got \(error)") }
        } catch { Issue.record("wrong error type: \(error)") }
    }

    @Test("an unreadable success body is a transport error")
    func unreadableSuccessBodyIsTransportError() async {
        let mock = MockTransport.returning(status: 200, body: nil)
        let client = HTTPClient(baseURL: "http://api.test", transport: mock)
        do {
            _ = try await client.get("/x", as: Item.self)
            Issue.record("expected HTTPError.transport")
        } catch let error as HTTPError {
            if case .transport = error {} else { Issue.record("expected .transport, got \(error)") }
        } catch { Issue.record("wrong error type: \(error)") }
    }

    @Test("a transport-thrown error propagates unchanged")
    func transportErrorPropagates() async {
        let mock = MockTransport { _ in throw HTTPError.transport("connection refused") }
        let client = HTTPClient(baseURL: "http://api.test", transport: mock)
        do {
            _ = try await client.get("/x", as: Item.self)
            Issue.record("expected HTTPError.transport")
        } catch let error as HTTPError {
            #expect(error == .transport("connection refused"))
        } catch { Issue.record("wrong error type: \(error)") }
    }
}
