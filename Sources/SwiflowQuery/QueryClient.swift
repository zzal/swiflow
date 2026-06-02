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
    /// A subscriber is "live" if its owner is alive; a missing scheduler
    /// just means markDirty is skipped for that subscriber (e.g. in tests
    /// where the scheduler is transient), but the subscription itself stays.
    func notify(_ key: QueryKey) {
        guard let subs = subscribers[key] else { return }
        var live: [Subscriber] = []
        for sub in subs {
            guard let owner = sub.owner else { continue }   // owner gone → prune
            if let scheduler = sub.scheduler {
                scheduler.markDirty(owner)
            }
            live.append(sub)
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
        // Clear the pending flag unconditionally — even when this call dedups to
        // an already-in-flight fetch (guard below returns), the entry must not
        // stay "pending" forever, which would wedge isFetching=true after that
        // fetch resolves.
        entry.hasPendingFetch = false
        guard entry.inFlight == nil, let boxedFetch = entry.boxedFetch else { return }
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
        // Guard BEFORE touching `inFlight`. If this fetch was superseded — a
        // newer fetch or an `invalidate` bumped the generation — then
        // `entry.inFlight` now holds the NEWER fetch's handle. Nil-ing it here
        // would lose dedup (a later `startFetch` would spawn a duplicate) and
        // corrupt `isFetching`/`settle()` bookkeeping for the live fetch. A
        // superseded result is simply dropped, leaving the newer fetch intact.
        guard entry.generation == generation else { return }
        entry.inFlight = nil
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
        // v1 notifies on every settle (both fetch start and completion) so
        // `isFetching` toggles and the SWR indicator clears; the VNode diff
        // absorbs identical-output re-renders. `entry.valuesEqual` is reserved
        // for markDirty-gating once `select` change-detection lands (deferred).
        notify(key)
    }

    /// All currently in-flight fetch tasks — awaited by the test harness.
    /// `package` (not `public`): only the in-package test harness needs it; the
    /// public surface stays `query` / `invalidate` / `QueryState` / `Query`.
    package func inFlightTasks() -> [Task<Void, Never>] {
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

    // MARK: - Reconciliation

    /// One component's observation of one key during a render (recorded by
    /// `observe`). Carries everything reconcile needs to create the entry and
    /// trigger a fetch.
    struct QueryObservation {
        let key: QueryKey
        let tags: Set<QueryTag>
        let staleTime: Duration
        let boxedFetch: @MainActor () async throws -> Any
        let valuesEqual: (Any?, Any?) -> Bool
    }

    /// Diff `owner`'s this-render observations against its previous set.
    func reconcile(owner: AnyComponent, scheduler: (any Scheduler)?,
                   observations: [QueryObservation]) {
        let ownerID = ObjectIdentifier(owner.instance)
        let newKeys = Set(observations.map(\.key))
        let oldKeys = observed[ownerID] ?? []

        // Dropped keys → unsubscribe.
        for key in oldKeys.subtracting(newKeys) {
            unsubscribe(ownerID: ownerID, from: key)
        }
        observed[ownerID] = newKeys.isEmpty ? nil : newKeys

        var triggered = Set<QueryKey>()
        for ob in observations {
            let entry = entries[ob.key] ?? {
                let e = QueryEntry(valuesEqual: ob.valuesEqual)
                entries[ob.key] = e
                return e
            }()
            entry.tags = ob.tags
            entry.boxedFetch = ob.boxedFetch          // capture latest deps

            if let scheduler { subscribe(owner: owner, scheduler: scheduler, to: ob.key) }

            // Trigger only for NEW observations (mount / key-change), gated by
            // staleness; once per key per render.
            let isNew = !oldKeys.contains(ob.key)
            if isNew, !triggered.contains(ob.key), needsFetch(entry, staleTime: ob.staleTime) {
                triggered.insert(ob.key)
                startFetch(for: ob.key, entry: entry)
            }
        }
    }

    /// Drop all of a component's subscriptions on unmount.
    func dropComponent(_ owner: AnyComponent) {
        let ownerID = ObjectIdentifier(owner.instance)
        for key in observed[ownerID] ?? [] {
            unsubscribe(ownerID: ownerID, from: key)
        }
        observed[ownerID] = nil
    }

    // MARK: - RenderObserver (per-render observation frames)

    /// One in-progress component render's collected observations.
    private struct Frame {
        let owner: AnyComponent
        let scheduler: (any Scheduler)?
        var observations: [QueryObservation] = []
    }
    private var frames: [Frame] = []

    /// Called by `query(_:)` during `body`: record interest, return the current
    /// snapshot. Pure read otherwise — no fetch, no subscription mutation here.
    func observe<Q: Query>(_ q: Q) -> QueryState<Q.Value> {
        let key = q.queryKey
        let ob = QueryObservation(
            key: key,
            tags: q.tags,
            staleTime: q.staleTime,
            boxedFetch: { try await q.fetch() },
            valuesEqual: { ($0 as? Q.Value) == ($1 as? Q.Value) }
        )
        if !frames.isEmpty { frames[frames.count - 1].observations.append(ob) }
        return makeSnapshot(from: entries[key], as: Q.Value.self)
    }
}

extension QueryClient: RenderObserver {
    package func willEvaluate(owner: AnyComponent, scheduler: (any Scheduler)?) {
        frames.append(Frame(owner: owner, scheduler: scheduler))
    }

    package func didEvaluate() {
        guard let frame = frames.popLast() else { return }
        reconcile(owner: frame.owner, scheduler: frame.scheduler,
                  observations: frame.observations)
    }

    package func componentDidUnmount(_ owner: AnyComponent) {
        dropComponent(owner)
    }
}
