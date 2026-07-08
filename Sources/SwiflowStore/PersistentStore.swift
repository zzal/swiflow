// Sources/SwiflowStore/PersistentStore.swift
//
// An async key/value store over the browser's IndexedDB — the persistence
// primitive Swiflow was missing. Values are `Codable`; they're written as a
// JSON string (via `JSONValueEncoder` + `JSONValue.jsonString`) and read back
// through `JSON.parse` + JavaScriptKit's `JSValueDecoder` (the decode half
// JavaScriptKit already ships).
//
// Why IndexedDB over `localStorage`: it's asynchronous (never blocks the main
// thread), stores far more than the ~5 MB string cap, and is the right general
// primitive for app state that should survive navigation *and* reload.
//
// WASM-only — IndexedDB lives in the browser. The `#else` host stub keeps the
// API present so app targets still typecheck off-WASM (where they never run).
//
// Split keyed on arch(wasm32), NOT canImport(JavaScriptKit): JavaScriptKit is
// an unconditional dependency, so canImport is TRUE on host — the "wasm"
// branch would compile on macOS and `init` would trap at `JSObject.global`
// the moment anything constructs a store (the @Persisted registry does).
// Same class of bug PR #160 fixed in SwiflowFetcher.

#if arch(wasm32)
import Swiflow
import JavaScriptKit
import SwiflowFetcher

/// A persistent key/value store backed by one IndexedDB object store.
///
/// ```swift
/// let store = PersistentStore()
/// try await store.save(pinned, forKey: "pinned-cities")
/// let restored = try await store.load([City].self, forKey: "pinned-cities")
/// ```
///
/// `@MainActor`: IndexedDB is single-threaded and these calls touch JS, so the
/// whole type is main-actor isolated (and thus `Sendable`).
@MainActor
public final class PersistentStore {
    private let databaseName: String
    private let storeName: String
    /// The opened `IDBDatabase`, cached after the first `database()` call.
    private var database: JSObject?
    /// The `onversionchange`/`onclose` handlers installed on the cached
    /// connection — retained here because `JSClosure` is ref-counted on the
    /// Swift side; replaced wholesale on each (re)open.
    private var connectionWatchers: [JSClosure] = []
    /// The in-flight open, memoized so concurrent first callers all await the
    /// SAME `open` request instead of each issuing their own `indexedDB.open`
    /// (which would leak every loser's connection — IndexedDB has no
    /// "cancel", so an abandoned open just sits there holding a connection
    /// open). Cleared once the open settles (success or failure) so a failed
    /// open can be retried by the next caller rather than replaying the
    /// same rejection forever.
    private var openTask: Task<DatabaseBox, Error>?

    /// - Parameters:
    ///   - database: IndexedDB database name. When omitted it defaults to the
    ///     document title (the app's name) — so the DB shows up as "Mission
    ///     Control" rather than a generic "swiflow" — falling back to "swiflow"
    ///     if the page has no title. Pass an explicit name to pin it; note that
    ///     changing the name later starts a fresh, empty database (data under
    ///     the old name is orphaned, not migrated).
    ///   - store: object-store name within the database.
    public init(database: String? = nil, store: String = "kv") {
        self.databaseName = database ?? Self.appName()
        self.storeName = store
    }

    /// The document title — the closest thing to an app name available at
    /// runtime — or "swiflow" when the page sets no title.
    private static func appName() -> String {
        if let title = JSObject.global.document.object?.title.string, !title.isEmpty {
            return title
        }
        return "swiflow"
    }

    // MARK: - Public API

    /// Decode the value stored at `key`, or `nil` if nothing is stored there.
    /// Throws `StoreError.decoding` if a stored value can't be decoded as `T`.
    public func load<T: Decodable>(_ type: T.Type, forKey key: String) async throws -> T? {
        let db = try await openedDatabase()
        let request = try requestOnStore(db, mode: "readonly") { try $0.get?(key) }
        try await awaitRequest(request)

        // A missing key resolves with `undefined`, so `.string` is nil — treat
        // both "absent" and "non-string" as "nothing to restore".
        guard let jsonString = request.result.string else { return nil }
        guard let parse = JSObject.global.JSON.object?.parse.function else { throw StoreError.unavailable }
        // `JSON.parse` throws on malformed input — call it as a throwing JS
        // function so corrupt stored data surfaces as `StoreError.decoding`
        // rather than trapping the wasm. (Our own writes are always valid; this
        // guards against tampering or a foreign writer to the same store.)
        do {
            let parsed = try parse.throws(jsonString)
            return try JSValueDecoder().decode(T.self, from: parsed)
        } catch {
            throw StoreError.decoding(String(describing: error))
        }
    }

    /// Encode and store `value` at `key`, replacing any previous value.
    public func save<T: Encodable>(_ value: T, forKey key: String) async throws {
        let jsonString = try JSONValueEncoder().encode(value).jsonString
        let db = try await openedDatabase()
        let request = try requestOnStore(db, mode: "readwrite") { try $0.put?(jsonString, key) }
        try await awaitRequest(request)
    }

    /// Delete whatever is stored at `key` (a no-op if nothing is).
    public func remove(forKey key: String) async throws {
        let db = try await openedDatabase()
        let request = try requestOnStore(db, mode: "readwrite") { try $0.delete?(key) }
        try await awaitRequest(request)
    }

    /// Opens a transaction, resolves the object store, and runs `operate` to
    /// issue the request — with every synchronous JS call made through
    /// `JSThrowingObject`, so a sync exception (`InvalidStateError` on a
    /// connection the browser or another tab closed, `TransactionInactiveError`,
    /// …) surfaces as `StoreError.request` instead of trapping the wasm.
    /// The old bang-call style only guarded nil RETURNS — the same intra-file
    /// inconsistency the audit flagged (`JSON.parse` used `.throws`, the IDB
    /// calls didn't).
    private func requestOnStore(
        _ db: JSObject,
        mode: String,
        _ operate: (JSThrowingObject) throws -> JSValue?
    ) throws -> JSObject {
        do {
            guard let tx = try JSThrowingObject(db).transaction?(storeName, mode).object,
                  let store = try JSThrowingObject(tx).objectStore?(storeName).object,
                  let request = try operate(JSThrowingObject(store))?.object else {
                throw StoreError.unavailable
            }
            return request
        } catch let error as StoreError {
            throw error
        } catch {
            throw StoreError.request(String(describing: error))
        }
    }

    // MARK: - IndexedDB plumbing

    /// Opens (and caches) the database, creating the object store on first use.
    ///
    /// Single-flight: if an open is already in progress (e.g. two concurrent
    /// first calls to `load`/`save`/`remove`), the second caller awaits the
    /// SAME `Task` rather than starting its own `indexedDB.open` — avoiding a
    /// leaked, never-closed second connection from the loser of the race.
    private func openedDatabase() async throws -> JSObject {
        if let database { return database }
        if let openTask { return try await openTask.value.value }

        let task = Task<DatabaseBox, Error> { [databaseName, storeName] in
            guard let factory = JSObject.global.indexedDB.object,
                  let request = factory.open!(databaseName, 1).object else {
                throw StoreError.unavailable
            }
            try await self.awaitRequest(request, onUpgradeNeeded: {
                // `onupgradeneeded` fires before `onsuccess` when the DB is
                // created or its version bumps — the only place an object
                // store may be made.
                guard let db = request.result.object else { return }
                let exists = db.objectStoreNames.object?.contains!(storeName).boolean ?? false
                if !exists { _ = db.createObjectStore!(storeName) }
            })
            guard let opened = request.result.object else { throw StoreError.unavailable }
            return DatabaseBox(opened)
        }
        openTask = task
        defer { openTask = nil }

        let opened = try await task.value.value
        database = opened
        installConnectionWatchers(on: opened)
        return opened
    }

    /// Self-evict when another tab upgrades or deletes this database
    /// (`onversionchange`) or the browser force-closes the connection
    /// (`onclose`, e.g. storage eviction). Without these, the cached handle
    /// went dead-but-cached: the other tab's upgrade BLOCKED forever on our
    /// open connection, and our next call hit a closed handle. After
    /// eviction the next operation reopens; if the database has since moved
    /// past our version (hardcoded 1 — this store's schema is a single kv
    /// object store, deliberately frozen), that open fails as a
    /// `StoreError`, a graceful degrade rather than a trap.
    private func installConnectionWatchers(on db: JSObject) {
        let onVersionChange = JSClosure { [weak self] _ in
            MainActor.assumeIsolated {
                // Close FIRST so the other tab's upgrade/delete can proceed,
                // then drop the cache so our next call reopens.
                _ = db.close!()
                self?.evictConnection()
            }
            return .undefined
        }
        let onClose = JSClosure { [weak self] _ in
            // The browser already closed the connection — just stop caching it.
            MainActor.assumeIsolated { self?.evictConnection() }
            return .undefined
        }
        db.onversionchange = .object(onVersionChange)
        db.onclose = .object(onClose)
        connectionWatchers = [onVersionChange, onClose]
    }

    private func evictConnection() {
        database = nil
        connectionWatchers = []
    }

    /// Bridges one `IDBRequest` to async/await: resumes when `onsuccess` fires,
    /// throws when `onerror` does. The request's `result`/`error` are read by the
    /// caller *after* the await (the request object stays alive in scope), so no
    /// non-`Sendable` `JSValue` crosses the continuation.
    ///
    /// JavaScriptKit ref-counts `JSClosure`s on the Swift side, so the handlers
    /// must outlive the synchronous setup below. A retainer ↔ closures reference
    /// cycle keeps them alive with no external owner; the first handler to fire
    /// breaks the cycle, releasing all of them.
    private func awaitRequest(_ request: JSObject, onUpgradeNeeded: (() -> Void)? = nil) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let retainer = ClosureRetainer()

            let onSuccess = JSClosure { _ in
                retainer.closures = []
                continuation.resume(returning: ())
                return .undefined
            }
            let onError = JSClosure { _ in
                retainer.closures = []
                let message = request.error.object?.message.string ?? "IndexedDB request failed"
                // DEBUG visibility (audit IV Wave-3): callers routinely
                // swallow these with `try?` (fire-and-forget saves), so a
                // quota-exceeded or version error would otherwise vanish.
                swiflowWarn("PersistentStore: IndexedDB request failed — \(message)")
                continuation.resume(throwing: StoreError.request(message))
                return .undefined
            }
            var closures = [onSuccess, onError]

            if let onUpgradeNeeded {
                let onUpgrade = JSClosure { _ in
                    onUpgradeNeeded()
                    return .undefined
                }
                closures.append(onUpgrade)
                request.onupgradeneeded = .object(onUpgrade)
            }

            retainer.closures = closures
            request.onsuccess = .object(onSuccess)
            request.onerror = .object(onError)
        }
    }
}

/// Holds in-flight `JSClosure`s alive across the synchronous continuation setup.
/// See `awaitRequest` for the retain-cycle lifetime trick.
private final class ClosureRetainer {
    var closures: [JSClosure] = []
}

/// Wraps a `JSObject` so it can be the `Success` type of an unstructured
/// `Task` — `Task.value` requires `Success: Sendable`, and `JSObject` isn't
/// (it's a JS-heap reference). `@unchecked Sendable` is safe here for the
/// same reason it is throughout this file: Swiflow is single-threaded wasm,
/// and every access (task body + all `openedDatabase()` callers) happens on
/// `@MainActor`.
private struct DatabaseBox: @unchecked Sendable {
    let value: JSObject
    init(_ value: JSObject) { self.value = value }
}

#else

/// Host stub: the real store needs a browser. Present so app targets typecheck
/// off-WASM; `load` always yields `nil`, writes are no-ops.
@MainActor
public final class PersistentStore {
    public init(database: String? = nil, store: String = "kv") {}
    public func load<T: Decodable>(_ type: T.Type, forKey key: String) async throws -> T? { nil }
    public func save<T: Encodable>(_ value: T, forKey key: String) async throws {}
    public func remove(forKey key: String) async throws {}
}

#endif

/// The persistence crossing behind `@Persisted`: async Codable key/value.
/// Minimal on purpose (no remove — YAGNI); `PersistentStore` conforms
/// verbatim on both the wasm and host-stub sides.
@MainActor
public protocol PersistedStorage: AnyObject {
    func load<T: Decodable>(_ type: T.Type, forKey key: String) async throws -> T?
    func save<T: Encodable>(_ value: T, forKey key: String) async throws
}

extension PersistentStore: PersistedStorage {}

/// Where `@Persisted`-emitted code resolves its store. ONE shared default
/// (kills per-component-connection waste; gives apps a single repoint
/// site); tests swap in a recording `MemoryStorage`. Underscored-public:
/// macro-emitted code in user modules must reach it.
@MainActor
public enum _PersistedStorageRegistry {
    public static var current: any PersistedStorage = PersistentStore()
}

/// Errors surfaced by `PersistentStore`.
public enum StoreError: Error, Sendable {
    /// IndexedDB isn't available (non-browser context, or storage disabled).
    case unavailable
    /// An IndexedDB request fired `onerror`; payload is its message.
    case request(String)
    /// A stored value couldn't be decoded into the requested type.
    case decoding(String)
}
