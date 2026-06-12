import Testing
import Swiflow
@testable import SwiflowQuery

/// A minimal hand-rolled component (no macro) usable as a subscriber owner.
@MainActor
private final class Dummy: Component {
    var body: VNode { .text("") }
}

@Suite("QueryClient/subscriptions")
@MainActor
struct QueryClientSubscriptionTests {
    private func makeOwner() -> AnyComponent { AnyComponent(Dummy()) }

    @Test("notify marks every live subscriber of the key dirty") func notifyMarksAllLiveSubscribers() {
        var marked: [ObjectIdentifier] = []
        let scheduler = SyncScheduler { marked.append(ObjectIdentifier($0.instance)) }
        let client = QueryClient(clock: ManualClock())

        let a = makeOwner(), b = makeOwner()
        client.subscribe(owner: a, scheduler: scheduler, to: ["k"])
        client.subscribe(owner: b, scheduler: scheduler, to: ["k"])

        client.notify(["k"])
        scheduler.flush()
        #expect(marked.count == 2)
        #expect(marked.contains(ObjectIdentifier(a.instance)))
        #expect(marked.contains(ObjectIdentifier(b.instance)))
    }

    @Test("An unsubscribed owner receives no further notifications") func unsubscribeStopsNotifications() {
        var markCount = 0
        let scheduler = SyncScheduler { _ in markCount += 1 }
        let client = QueryClient(clock: ManualClock())
        let a = makeOwner()
        client.subscribe(owner: a, scheduler: scheduler, to: ["k"])
        client.unsubscribe(ownerID: ObjectIdentifier(a.instance), from: ["k"])
        client.notify(["k"])
        scheduler.flush()
        #expect(markCount == 0)
    }

    @Test("Duplicate subscribe calls for the same owner notify only once") func subscribeIsIdempotentPerOwner() {
        var markCount = 0
        let scheduler = SyncScheduler { _ in markCount += 1 }
        let client = QueryClient(clock: ManualClock())
        let a = makeOwner()
        client.subscribe(owner: a, scheduler: scheduler, to: ["k"])
        client.subscribe(owner: a, scheduler: scheduler, to: ["k"])  // dup
        client.notify(["k"])
        scheduler.flush()
        #expect(markCount == 1)
    }
}
