import Testing
import Swiflow
@testable import SwiflowQuery

@MainActor
private final class Dummy: Component { var body: VNode { .text("") } }

/// Holds strong refs to AnyComponent wrappers so the weak Subscriber refs
/// inside QueryClient stay alive for the duration of each test.
@MainActor
private final class OwnerBag {
    var owners: [AnyComponent] = []
    func keep(_ owner: AnyComponent) { owners.append(owner) }
}

@Suite("QueryClient/invalidate")
@MainActor
struct QueryClientInvalidateTests {
    private func awaitInFlight(_ c: QueryClient) async {
        for t in c.inFlightTasks() { await t.value }
    }

    @discardableResult
    private func seed(_ client: QueryClient, _ key: QueryKey, tags: Set<QueryTag> = [],
                      bag: OwnerBag, counter: @escaping () -> Void) -> QueryEntry {
        let e = QueryEntry()
        e.boxedFetch = { counter(); return 1 }
        e.value = 1
        e.lastFetched = .zero
        e.tags = tags
        client.entries[key] = e
        let owner = AnyComponent(Dummy())
        bag.keep(owner)
        client.subscribe(owner: owner,
                         scheduler: SyncScheduler { _ in }, to: key)
        return e
    }

    @Test("Prefix invalidate refetches every key under the prefix and nothing else") func prefixCascadeRefetchesMatches() async {
        let client = QueryClient(clock: ManualClock())
        let bag = OwnerBag()
        var u1 = 0, u1posts = 0, teams = 0
        seed(client, ["users", 1], bag: bag) { u1 += 1 }
        seed(client, ["users", 1, "posts"], bag: bag) { u1posts += 1 }
        seed(client, ["teams", 1], bag: bag) { teams += 1 }

        client.invalidate(["users"])
        await awaitInFlight(client)

        #expect(u1 == 1)
        #expect(u1posts == 1)
        #expect(teams == 0)
    }

    @Test("exact: true invalidates only the exact key, not its descendants") func exactInvalidatesOnlyTheExactKey() async {
        let client = QueryClient(clock: ManualClock())
        let bag = OwnerBag()
        var u1 = 0, u1posts = 0
        seed(client, ["users", 1], bag: bag) { u1 += 1 }
        seed(client, ["users", 1, "posts"], bag: bag) { u1posts += 1 }

        client.invalidate(["users", 1], exact: true)
        await awaitInFlight(client)
        #expect(u1 == 1)
        #expect(u1posts == 0)
    }

    @Test("Tag invalidate refetches only entries carrying that tag") func tagCascadeRefetchesMatches() async {
        let client = QueryClient(clock: ManualClock())
        let bag = OwnerBag()
        var a = 0, b = 0
        seed(client, ["users", 1], tags: ["team:3"], bag: bag) { a += 1 }
        seed(client, ["users", 2], tags: ["team:9"], bag: bag) { b += 1 }

        client.invalidate(tag: "team:3")
        await awaitInFlight(client)
        #expect(a == 1)
        #expect(b == 0)
    }
}
