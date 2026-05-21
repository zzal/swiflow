import Testing
@testable import SwiflowRouter

@Suite("RouterContext")
struct RouterContextTests {

    @Test("path field stored correctly")
    func pathField() {
        let ctx = RouterContext(path: "/users/42", params: ["id": "42"], query: [:])
        #expect(ctx.path == "/users/42")
    }

    @Test("params field stored correctly")
    func paramsField() {
        let ctx = RouterContext(path: "/", params: ["id": "7"], query: [:])
        #expect(ctx.params["id"] == "7")
    }

    @Test("query field stored correctly")
    func queryField() {
        let ctx = RouterContext(path: "/search", params: [:], query: ["q": "swift", "page": "2"])
        #expect(ctx.query["q"] == "swift")
        #expect(ctx.query["page"] == "2")
    }

    @Test("default init has empty params and query")
    func defaultInit() {
        let ctx = RouterContext(path: "/")
        #expect(ctx.params.isEmpty)
        #expect(ctx.query.isEmpty)
    }
}
