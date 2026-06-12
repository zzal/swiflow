import Testing
@testable import SwiflowQuery

@Suite("QueryKey")
struct KeysTests {
    @Test("Array-literal keys build typed string and int components") func literalsBuildComponents() {
        let k: QueryKey = ["users", 1]
        #expect(k == [.string("users"), .int(1)])
    }

    @Test(".int(1) and .string(\"1\") are distinct key components") func intAndStringAreDistinct() {
        #expect(QueryKeyComponent.int(1) != QueryKeyComponent.string("1"))
    }

    @Test("hasPrefix matches every leading subsequence, including the full key") func prefixMatches() {
        let entry: QueryKey = ["users", 1, "posts"]
        #expect(entry.hasPrefix(["users"]))
        #expect(entry.hasPrefix(["users", 1]))
        #expect(entry.hasPrefix(["users", 1, "posts"]))
    }

    @Test("hasPrefix rejects diverging, unrelated, and longer-than-key candidates") func nonPrefixDoesNotMatch() {
        let entry: QueryKey = ["users", 1]
        #expect(!entry.hasPrefix(["users", 2]))
        #expect(!entry.hasPrefix(["teams"]))
        #expect(!entry.hasPrefix(["users", 1, "posts"]))
    }
}
