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

    // MARK: - Fetch lifecycle

    /// Spawn the entry's fetch if none is in flight (dedup). The task captures
    /// the entry's current generation and commits only if it still matches.
    func startFetch(for key: QueryKey, entry: QueryEntry) {
        guard entry.inFlight == nil, let boxedFetch = entry.boxedFetch else { return }
        entry.hasPendingFetch = false
        let generation = entry.generation
        entry.inFlight = Task { [weak self] in
            let result: Result<Any, any Error>
            do { result = .success(try await boxedFetch()) }
            catch { result = .failure(error) }
            self?.commitFetch(key: key, generation: generation, result: result)
        }
        // Reflect isFetching for any current subscribers (background spinner /
        // first-load). Identical-output re-renders are absorbed by the diff.
        notify(key)
    }

    private func commitFetch(key: QueryKey, generation: Int, result: Result<Any, any Error>) {
        guard let entry = entries[key] else { return }
        entry.inFlight = nil
        guard entry.generation == generation else { return }   // superseded → drop
        switch result {
        case .success(let value):
            entry.value = value
            entry.error = nil
            entry.lastFetched = clock.now()
        case .failure(let err):
            entry.error = err
            // Leave `lastFetched` unchanged: a failed fetch stays stale so the
            // next trigger retries.
        }
        notify(key)
    }

    /// All currently in-flight fetch tasks — awaited by the test harness.
    public func inFlightTasks() -> [Task<Void, Never>] {
        entries.values.compactMap { $0.inFlight }
    }

    // MARK: - Freshness

    /// Whether a *triggered* observation of this entry should revalidate.
    /// `lastFetched == nil` (never succeeded / forced stale) always fetches.
    func needsFetch(_ entry: QueryEntry, staleTime: Duration) -> Bool {
        guard let last = entry.lastFetched else { return true }
        return (clock.now() - last) >= staleTime
    }

    // MARK: - Invalidation

    /// Force every entry whose key starts with `key` (or equals it when
    /// `exact`) stale, and refetch the ones with live subscribers.
    public func invalidate(_ key: QueryKey, exact: Bool = false) {
        for (entryKey, entry) in entries {
            let match = exact ? (entryKey == key) : entryKey.hasPrefix(key)
            if match { forceStaleAndRefetch(entryKey, entry) }
        }
    }

    /// Force every entry tagged `tag` stale, and refetch the live ones.
    public func invalidate(tag: QueryTag) {
        for (entryKey, entry) in entries where entry.tags.contains(tag) {
            forceStaleAndRefetch(entryKey, entry)
        }
    }

    private func forceStaleAndRefetch(_ key: QueryKey, _ entry: QueryEntry) {
        entry.lastFetched = nil          // force stale
        entry.generation += 1            // supersede any in-flight result
        entry.inFlight?.cancel()
        entry.inFlight = nil
        if hasLiveSubscribers(key) {
            startFetch(for: key, entry: entry)
        }
    }
}
