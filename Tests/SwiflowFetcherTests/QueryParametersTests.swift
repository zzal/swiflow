// Tests/SwiflowFetcherTests/QueryParametersTests.swift
//
// Host tests for the typed `query:` parameters (audit II Wave-3): the
// percent-encoder's character policy, value rendering, deterministic
// assembly, and the client-level URL composition — through a mock transport,
// like the rest of the HTTPClient suite.
import Testing
import Swiflow
@testable import SwiflowFetcher

/// Minimal scripted transport for URL assertions (the HTTPClientTests mock,
/// trimmed to what these tests need).
private final class MockTransport: HTTPTransport, @unchecked Sendable {
    private(set) var requests: [HTTPRequest] = []
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        requests.append(request)
        return HTTPResponse(status: 200, body: #"{"id":1,"name":"a"}"#)
    }
    var last: HTTPRequest? { requests.last }
}

private struct Item: Decodable, Equatable, Sendable { let id: Int; let name: String }

@Suite("URL query parameters")
struct QueryParametersTests {

    // MARK: - Percent-encoding policy

    @Test("unreserved characters pass through untouched")
    func unreservedPassThrough() {
        let unreserved = "AZaz09-._~"
        #expect(QueryStringEncoding.encodeComponent(unreserved) == unreserved)
    }

    @Test("reserved and structural characters are percent-encoded")
    func reservedAreEncoded() {
        // Space is %20 (never "+"), and "+" itself is %2B — unambiguous under
        // both RFC-3986 and WHATWG form decoding.
        let cases: [(String, String)] = [
            (" ", "%20"),
            ("+", "%2B"),
            ("&", "%26"),
            ("=", "%3D"),
            ("?", "%3F"),
            ("#", "%23"),
            ("/", "%2F"),
            ("%", "%25"),
            ("\"", "%22"),
        ]
        for (raw, encoded) in cases {
            #expect(QueryStringEncoding.encodeComponent(raw) == encoded, "\(raw)")
        }
    }

    @Test("non-ASCII encodes every UTF-8 byte")
    func nonASCIIEncodesUTF8Bytes() {
        #expect(QueryStringEncoding.encodeComponent("é") == "%C3%A9")
        #expect(QueryStringEncoding.encodeComponent("東京") == "%E6%9D%B1%E4%BA%AC")
        #expect(QueryStringEncoding.encodeComponent("🌦") == "%F0%9F%8C%A6")
        #expect(QueryStringEncoding.encodeComponent("Montréal") == "Montr%C3%A9al")
    }

    // MARK: - Value rendering

    @Test("each value case renders its canonical text")
    func valueRendering() {
        #expect(HTTPQueryValue.string("auto").text == "auto")
        #expect(HTTPQueryValue.int(-3).text == "-3")
        #expect(HTTPQueryValue.double(45.50884).text == "45.50884")
        #expect(HTTPQueryValue.bool(true).text == "true")
        #expect(HTTPQueryValue.bool(false).text == "false")
    }

    @Test("non-finite doubles render like URLSearchParams, not as invalid tokens")
    func nonFiniteDoublesRenderLikeJS() {
        #expect(HTTPQueryValue.double(.nan).text == "NaN")
        #expect(HTTPQueryValue.double(.infinity).text == "Infinity")
        #expect(HTTPQueryValue.double(-.infinity).text == "-Infinity")
    }

    @Test("literals map to the expected cases")
    func literalConformances() {
        let q: [String: HTTPQueryValue] = ["s": "auto", "i": 5, "d": 45.5, "b": true]
        #expect(q["s"] == .string("auto"))
        #expect(q["i"] == .int(5))
        #expect(q["d"] == .double(45.5))
        #expect(q["b"] == .bool(true))
    }

    // MARK: - Assembly

    @Test("queryString sorts keys for deterministic output")
    func queryStringSortsKeys() {
        let qs = QueryStringEncoding.queryString(["b": 2, "a": 1, "c": 3])
        #expect(qs == "a=1&b=2&c=3")
    }

    @Test("queryString encodes both key and value")
    func queryStringEncodesKeyAndValue() {
        #expect(QueryStringEncoding.queryString(["a b": .string("c&d")]) == "a%20b=c%26d")
    }

    @Test("an empty dictionary assembles to an empty string")
    func emptyDictionaryIsEmptyString() {
        #expect(QueryStringEncoding.queryString([:]) == "")
    }

    // MARK: - Client-level composition

    @Test("get appends ?key=value to the resolved URL")
    func getAppendsQuery() async throws {
        let mock = MockTransport()
        let client = HTTPClient(baseURL: "http://api.test", transport: mock)
        _ = try await client.get("/v1/search", query: ["name": .string("São Paulo"), "count": 5], as: Item.self)
        #expect(mock.last?.url == "http://api.test/v1/search?count=5&name=S%C3%A3o%20Paulo")
    }

    @Test("a path that already carries a query string is joined with &")
    func existingQueryJoinsWithAmpersand() async throws {
        let mock = MockTransport()
        let client = HTTPClient(baseURL: "http://api.test", transport: mock)
        _ = try await client.get("/v1/search?limit=1", query: ["name": "x"], as: Item.self)
        #expect(mock.last?.url == "http://api.test/v1/search?limit=1&name=x")
    }

    @Test("an empty query leaves the URL untouched")
    func emptyQueryLeavesURL() async throws {
        let mock = MockTransport()
        let client = HTTPClient(baseURL: "http://api.test", transport: mock)
        _ = try await client.get("/v1/search", query: [:], as: Item.self)
        #expect(mock.last?.url == "http://api.test/v1/search")
    }

    @Test("body verbs and delete carry query parameters too")
    func bodyVerbsAndDeleteCarryQuery() async throws {
        let mock = MockTransport()
        let client = HTTPClient(baseURL: "http://api.test", transport: mock)

        _ = try await client.post("/todos", json: ["title": .string("t")], query: ["dry_run": true], as: Item.self)
        #expect(mock.last?.url == "http://api.test/todos?dry_run=true")
        #expect(mock.last?.body == JSONValue.object(["title": .string("t")]).jsonString)

        try await client.delete("/todos/1", query: ["soft": true])
        #expect(mock.last?.url == "http://api.test/todos/1?soft=true")
    }
}
