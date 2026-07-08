// Sources/SwiflowStore/StoreKey.swift

/// A typed storage key: name + value type in ONE declaration, so the type
/// can never drift between the save site and the load sites (with stringly
/// keys, every `load(SomeType.self, forKey:)` restates the type and a
/// mismatch reads as "nothing stored").
///
/// ```swift
/// static let pinnedKey = StoreKey<[City]>("pinned-cities")
///
/// try await store.save(pinned, for: Self.pinnedKey)
/// let restored = try await store.load(Self.pinnedKey)   // [City]? — inferred
/// ```
public struct StoreKey<Value: Codable>: Sendable {
    public let name: String
    public init(_ name: String) { self.name = name }
}

/// Typed accessors on the protocol, so every `PersistedStorage` — the real
/// `PersistentStore` and test doubles alike — gets the same surface.
public extension PersistedStorage {
    func load<V>(_ key: StoreKey<V>) async throws -> V? {
        try await load(V.self, forKey: key.name)
    }

    func save<V>(_ value: V, for key: StoreKey<V>) async throws {
        try await save(value, forKey: key.name)
    }
}

public extension PersistentStore {
    /// `remove` lives on the concrete store (the `PersistedStorage` protocol
    /// is deliberately minimal — load/save is all @Persisted needs).
    func remove<V>(_ key: StoreKey<V>) async throws {
        try await remove(forKey: key.name)
    }
}
