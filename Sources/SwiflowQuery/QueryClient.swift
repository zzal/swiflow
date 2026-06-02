// Sources/SwiflowQuery/QueryClient.swift
import Swiflow

/// Owns the shared query cache, per-key subscriptions, the fetch lifecycle,
/// invalidation, and per-render subscription reconciliation. One instance per
/// render root, installed as that root's `RenderObserver` (later tasks).
@MainActor
public final class QueryClient {
    let clock: any QueryClock
    var entries: [QueryKey: QueryEntry] = [:]
    var subscribers: [QueryKey: [Subscriber]] = [:]
    /// Per owner-instance: the set of keys it observed in its last render.
    var observed: [ObjectIdentifier: Set<QueryKey>] = [:]

    public init(clock: any QueryClock = SystemQueryClock()) {
        self.clock = clock
    }

    /// A weak reference to one subscribing component + its scheduler.
    struct Subscriber {
        weak var owner: AnyComponent?
        weak var scheduler: (any Scheduler)?
    }

    // MARK: - Subscriptions

    func subscribe(owner: AnyComponent, scheduler: any Scheduler, to key: QueryKey) {
        var subs = subscribers[key] ?? []
        let id = ObjectIdentifier(owner.instance)
        let already = subs.contains { sub in
            sub.owner.map { ObjectIdentifier($0.instance) } == id
        }
        if !already {
            subs.append(Subscriber(owner: owner, scheduler: scheduler))
        }
        subscribers[key] = subs
    }

    func unsubscribe(ownerID: ObjectIdentifier, from key: QueryKey) {
        guard var subs = subscribers[key] else { return }
        subs.removeAll { sub in
            guard let owner = sub.owner else { return true }
            return ObjectIdentifier(owner.instance) == ownerID
        }
        subscribers[key] = subs.isEmpty ? nil : subs
    }

    /// Mark every live subscriber of `key` dirty, pruning dead weak refs.
    func notify(_ key: QueryKey) {
        guard let subs = subscribers[key] else { return }
        var live: [Subscriber] = []
        for sub in subs {
            if let owner = sub.owner, let scheduler = sub.scheduler {
                scheduler.markDirty(owner)
                live.append(sub)
            }
        }
        subscribers[key] = live.isEmpty ? nil : live
    }

    /// True iff `key` currently has at least one live subscriber.
    func hasLiveSubscribers(_ key: QueryKey) -> Bool {
        guard let subs = subscribers[key] else { return false }
        return subs.contains { $0.owner != nil }
    }
}
