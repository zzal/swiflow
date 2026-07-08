// Tests/SwiflowStoreTests/PersistedStorageTests.swift
//
// Audit IV Wave-2 #5: the storage seam behind @Persisted. PersistentStore
// conforms verbatim; the registry is the single resolve point macro-emitted
// code uses, swappable in tests (the Navigator/HTTPTransport house move).
import Testing
@testable import SwiflowStore

@Suite("PersistedStorage seam")
struct PersistedStorageTests {

    @Test("registry default is a PersistentStore; swap + restore works")
    @MainActor
    func registrySwaps() async throws {
        let prior = _PersistedStorageRegistry.current
        defer { _PersistedStorageRegistry.current = prior }
        #expect(prior is PersistentStore)

        let memory = MemoryStorage()
        _PersistedStorageRegistry.current = memory
        try await _PersistedStorageRegistry.current.save("x", forKey: "k")
        let roundTrip = try await _PersistedStorageRegistry.current.load(String.self, forKey: "k")
        #expect(roundTrip == "x")
        #expect(memory.saves.map(\.key) == ["k"])
        #expect(memory.loadedKeys == ["k"])
    }
}
