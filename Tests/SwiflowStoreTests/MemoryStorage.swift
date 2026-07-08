// Tests/SwiflowStoreTests/MemoryStorage.swift
import SwiflowStore

/// Recording in-memory `PersistedStorage` (the MockNavigator house style):
/// seed `values` before mount, assert on `loadedKeys`/`saves` after.
/// Values are held as `Any` and cast on load — mirrors "whatever was
/// stored comes back if the type matches, nil otherwise".
@MainActor
final class MemoryStorage: PersistedStorage {
    var values: [String: Any] = [:]
    private(set) var loadedKeys: [String] = []
    private(set) var saves: [(key: String, value: Any)] = []

    func load<T: Decodable>(_ type: T.Type, forKey key: String) async throws -> T? {
        loadedKeys.append(key)
        return values[key] as? T
    }

    func save<T: Encodable>(_ value: T, forKey key: String) async throws {
        saves.append((key: key, value: value))
        values[key] = value
    }
}
