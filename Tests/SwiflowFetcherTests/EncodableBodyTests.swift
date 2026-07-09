// Tests/SwiflowFetcherTests/EncodableBodyTests.swift
//
// Host tests for the typed `body:` overloads (audit II Wave-3): an Encodable
// value serializes through JSONValueEncoder into the same request pipeline as
// `json:` — Content-Type forced, query params composing — and a body whose
// own encode(to:) throws surfaces that error unchanged, before any request.
import Testing
import Swiflow
@testable import SwiflowFetcher

private final class MockTransport: HTTPTransport, @unchecked Sendable {
    private(set) var requests: [HTTPRequest] = []
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        requests.append(request)
        return HTTPResponse(status: 200, body: #"{"id":1,"name":"a"}"#)
    }
    var last: HTTPRequest? { requests.last }
}

private struct Item: Decodable, Equatable, Sendable { let id: Int; let name: String }

private struct NewTodo: Encodable, Sendable {
    let title: String
    let done: Bool
    let tags: [String]
    let note: String?   // nil → key omitted (synthesized encodeIfPresent)
}

private struct Sabotaged: Encodable, Sendable {
    struct Refusal: Error, Equatable {}
    func encode(to encoder: any Encoder) throws { throw Refusal() }
}

@Suite("Encodable request bodies")
struct EncodableBodyTests {

    @Test("post(body:) serializes the Encodable value as the JSON body")
    func postEncodesBody() async throws {
        let mock = MockTransport()
        let client = HTTPClient(baseURL: "http://api.test", transport: mock)
        _ = try await client.post(
            "/todos",
            body: NewTodo(title: "write docs", done: false, tags: ["a", "b"], note: nil),
            as: Item.self)
        // jsonString emits sorted keys; the nil optional is omitted entirely.
        #expect(mock.last?.body == #"{"done":false,"tags":["a","b"],"title":"write docs"}"#)
        #expect(mock.last?.headers["Content-Type"] == "application/json")
        #expect(mock.last?.method == "POST")
    }

    @Test("put and patch carry Encodable bodies too, composing with query:")
    func putAndPatchCarryBodies() async throws {
        let mock = MockTransport()
        let client = HTTPClient(baseURL: "http://api.test", transport: mock)

        _ = try await client.put("/todos/1", body: ["done": true], query: ["notify": false], as: Item.self)
        #expect(mock.last?.method == "PUT")
        #expect(mock.last?.url == "http://api.test/todos/1?notify=false")
        #expect(mock.last?.body == #"{"done":true}"#)

        _ = try await client.patch("/todos/1", body: ["title": "renamed"], as: Item.self)
        #expect(mock.last?.method == "PATCH")
        #expect(mock.last?.body == #"{"title":"renamed"}"#)
    }

    @Test("a body whose encode(to:) throws rethrows that error unchanged — no request is sent")
    func encodeFailurePassesThroughBeforeSending() async {
        let mock = MockTransport()
        let client = HTTPClient(baseURL: "http://api.test", transport: mock)
        do {
            _ = try await client.post("/x", body: Sabotaged(), as: Item.self)
            Issue.record("expected Sabotaged.Refusal")
        } catch let error as Sabotaged.Refusal {
            #expect(error == Sabotaged.Refusal())
        } catch { Issue.record("wrong error type: \(error)") }
        #expect(mock.requests.isEmpty, "the failed encode must abort before the transport")
    }

    @Test("json: and body: overloads coexist — distinct labels, same pipeline")
    func jsonAndBodyCoexist() async throws {
        let mock = MockTransport()
        let client = HTTPClient(baseURL: "http://api.test", transport: mock)
        _ = try await client.post("/a", json: ["k": .string("v")], as: Item.self)
        let viaJSON = mock.last?.body
        _ = try await client.post("/a", body: ["k": "v"], as: Item.self)
        #expect(mock.last?.body == viaJSON)
    }
}
