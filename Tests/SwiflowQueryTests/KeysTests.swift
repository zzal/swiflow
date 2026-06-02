import Testing
@testable import SwiflowQuery

@Suite("QueryKey")
struct KeysTests {
    @Test func literalsBuildComponents() {
        let k: QueryKey = ["users", 1]
        #expect(k == [.string("users"), .int(1)])
    }

    @Test func intAndStringAreDistinct() {
        #expect(QueryKeyComponent.int(1) != QueryKeyComponent.string("1"))
    }

    @Test func prefixMatches() {
        let entry: QueryKey = ["users", 1, "posts"]
        #expect(entry.hasPrefix(["users"]))
        #expect(entry.hasPrefix(["users", 1]))
        #expect(entry.hasPrefix(["users", 1, "posts"]))
    }

    @Test func nonPrefixDoesNotMatch() {
        let entry: QueryKey = ["users", 1]
        #expect(!entry.hasPrefix(["users", 2]))
        #expect(!entry.hasPrefix(["teams"]))
        #expect(!entry.hasPrefix(["users", 1, "posts"]))
    }
}
