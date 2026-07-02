// Tests/SwiflowFetcherTests/HTTPErrorTests.swift
import Testing
@testable import SwiflowFetcher

@Suite("HTTPError")
struct HTTPErrorTests {
    @Test(".status carries the response body and folds it into description")
    func statusCarriesBody() {
        let withBody = HTTPError.status(404, body: "not found")
        #expect(withBody.description == "HTTP 404: not found")

        let noBody = HTTPError.status(500, body: nil)
        #expect(noBody.description == "HTTP 500")

        let emptyBody = HTTPError.status(500, body: "")
        #expect(emptyBody.description == "HTTP 500")
    }

    @Test(".status is Equatable on both status and body")
    func statusEquatable() {
        #expect(HTTPError.status(404, body: "x") == HTTPError.status(404, body: "x"))
        #expect(HTTPError.status(404, body: "x") != HTTPError.status(404, body: "y"))
        #expect(HTTPError.status(404, body: nil) != HTTPError.status(404, body: ""))
    }
}
