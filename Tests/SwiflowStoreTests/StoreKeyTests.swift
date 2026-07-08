// Tests/SwiflowStoreTests/StoreKeyTests.swift
//
// Audit IV Wave-3: typed StoreKey<Value> — key name + value type in ONE
// declaration, killing the `load(String.self, forKey:)` restatement where
// the type at every load site could silently drift from what save wrote.
import Testing
@testable import SwiflowStore

@Suite("StoreKey")
struct StoreKeyTests {

    @Test("typed round-trip through any PersistedStorage — no type restatement")
    @MainActor
    func typedRoundTrip() async throws {
        let memory = MemoryStorage()
        let pinned = StoreKey<[String]>("pinned-cities")

        try await memory.save(["Lyon", "Osaka"], for: pinned)
        let restored = try await memory.load(pinned)
        #expect(restored == ["Lyon", "Osaka"])
        #expect(memory.saves.map(\.key) == ["pinned-cities"], "the key's name is the storage key")
    }

    @Test("missing key loads nil")
    @MainActor
    func missingLoadsNil() async throws {
        let memory = MemoryStorage()
        let unit = StoreKey<String>("weather-unit")
        let restored = try await memory.load(unit)
        #expect(restored == nil)
    }

    @Test("PersistentStore gets the typed surface too (host stub: inert but well-typed)")
    @MainActor
    func persistentStoreOverloads() async throws {
        let store = PersistentStore()
        let unit = StoreKey<String>("weather-unit")
        try await store.save("celsius", for: unit)          // host: no-op
        let restored = try await store.load(unit)           // host: nil
        #expect(restored == nil)
        try await store.remove(unit)                        // host: no-op
    }
}
