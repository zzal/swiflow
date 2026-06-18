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

#if canImport(JavaScriptKit)
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
        guard let tx = db.transaction!(storeName, "readonly").object,
              let objectStore = tx.objectStore!(storeName).object,
              let request = objectStore.get!(key).object else {
            throw StoreError.unavailable
        }
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
        guard let tx = db.transaction!(storeName, "readwrite").object,
              let objectStore = tx.objectStore!(storeName).object,
              let request = objectStore.put!(jsonString, key).object else {
            throw StoreError.unavailable
        }
        try await awaitRequest(request)
    }

    /// Delete whatever is stored at `key` (a no-op if nothing is).
    public func remove(forKey key: String) async throws {
        let db = try await openedDatabase()
        guard let tx = db.transaction!(storeName, "readwrite").object,
              let objectStore = tx.objectStore!(storeName).object,
              let request = objectStore.delete!(key).object else {
            throw StoreError.unavailable
        }
        try await awaitRequest(request)
    }

    // MARK: - IndexedDB plumbing

    /// Opens (and caches) the database, creating the object store on first use.
    private func openedDatabase() async throws -> JSObject {
        if let database { return database }
        guard let factory = JSObject.global.indexedDB.object,
              let request = factory.open!(databaseName, 1).object else {
            throw StoreError.unavailable
        }
        let storeName = self.storeName
        try await awaitRequest(request, onUpgradeNeeded: {
            // `onupgradeneeded` fires before `onsuccess` when the DB is created
            // or its version bumps — the only place an object store may be made.
            guard let db = request.result.object else { return }
            let exists = db.objectStoreNames.object?.contains!(storeName).boolean ?? false
            if !exists { _ = db.createObjectStore!(storeName) }
        })
        guard let opened = request.result.object else { throw StoreError.unavailable }
        database = opened
        return opened
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

/// Errors surfaced by `PersistentStore`.
public enum StoreError: Error, Sendable {
    /// IndexedDB isn't available (non-browser context, or storage disabled).
    case unavailable
    /// An IndexedDB request fired `onerror`; payload is its message.
    case request(String)
    /// A stored value couldn't be decoded into the requested type.
    case decoding(String)
}
