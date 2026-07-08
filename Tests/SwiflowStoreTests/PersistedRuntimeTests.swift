// Tests/SwiflowStoreTests/PersistedRuntimeTests.swift
//
// Audit IV Wave-2 #5: the @Persisted full loop on host — MemoryStorage
// through the REAL harness (TestRenderer reuses firePostRenderLifecycle,
// so the mount hook and hydration run exactly as in the browser). Loop
// tests await _swiflowHydratePersisted() DIRECTLY for determinism; the
// fire-and-forget mount Task is covered separately with a bounded wait.
import Testing
import Swiflow
import SwiflowStore
@testable import SwiflowTesting

@Component
private final class FilterPage {
    @Persisted var magnitude: String = "2.5"
    @Persisted("legacy-window") var window: String = "day"
    var body: VNode { p("\(magnitude)|\(window)") }
}

// .serialized: the registry is process-global mutable state, and the emitted
// save/hydrate Tasks are fire-and-forget — under parallel execution one
// test's pending Task can run after ANOTHER test swapped the registry (the
// exact flake this suite shipped with). Serialization plus the drain in
// `withMemoryStorage` (yields before restoring, so stray Tasks land in THIS
// test's storage) makes the global seam safe.
//
// COROLLARY: this suite must be the ONLY one that touches the registry.
// `.serialized` serializes within a suite, not across suites — a separate
// registry-touching suite races this one at await points (a standalone
// seam suite shipped exactly that flake; its test now lives here).
@Suite("@Persisted full loop (MemoryStorage through the real harness)", .serialized)
struct PersistedRuntimeTests {

    @MainActor
    private func withMemoryStorage<T>(_ body: (MemoryStorage) async throws -> T) async rethrows -> T {
        let prior = _PersistedStorageRegistry.current
        let memory = MemoryStorage()
        _PersistedStorageRegistry.current = memory
        defer { _PersistedStorageRegistry.current = prior }
        let result = try await body(memory)
        // Drain fire-and-forget mount/save Tasks spawned during the body so
        // none outlives this test's registry installation.
        for _ in 0..<20 { await Task.yield() }
        return result
    }

    @Test("the seam: registry default is a PersistentStore; swap + typed round-trip works")
    @MainActor
    func registrySwaps() async throws {
        // Sound ONLY because this suite is serialized and nothing else
        // touches the registry — see the suite comment.
        #expect(_PersistedStorageRegistry.current is PersistentStore)
        try await withMemoryStorage { memory in
            try await _PersistedStorageRegistry.current.save("x", forKey: "k")
            let roundTrip = try await _PersistedStorageRegistry.current.load(String.self, forKey: "k")
            #expect(roundTrip == "x")
            #expect(memory.saves.map(\.key) == ["k"])
            #expect(memory.loadedKeys == ["k"])
        }
    }

    @Test("default paints first; hydrate restores stored values and repaints")
    @MainActor
    func hydrateRestores() async throws {
        try await withMemoryStorage { memory in
            memory.values["FilterPage.magnitude"] = "4.5"
            let page = FilterPage()
            let h = render(page)
            #expect(h.find("p")?.text == "2.5|day", "async hydration paints the default first")

            await page._swiflowHydratePersisted()   // deterministic loop coverage
            h.renderer.scheduler.flush()
            #expect(h.find("p")?.text == "4.5|day")
            #expect(memory.loadedKeys.contains("FilterPage.magnitude"), "auto-namespaced")
            #expect(memory.loadedKeys.contains("legacy-window"), "explicit key verbatim")
        }
    }

    @Test("mount fires the hydration Task through _swiflowDidMount (bounded wait)")
    @MainActor
    func mountTriggersHydration() async throws {
        try await withMemoryStorage { memory in
            let page = FilterPage()
            _ = render(page)
            for _ in 0..<50 where memory.loadedKeys.isEmpty { await Task.yield() }
            #expect(!memory.loadedKeys.isEmpty, "the mount hook spawned the hydrate Task")
        }
    }

    @Test("a write saves under the derived key; hydration does NOT echo-save")
    @MainActor
    func writeSavesHydrationDoesNot() async throws {
        try await withMemoryStorage { memory in
            memory.values["FilterPage.magnitude"] = "4.5"
            let page = FilterPage()
            let h = render(page)
            await page._swiflowHydratePersisted()
            #expect(memory.saves.isEmpty, "hydration assignments are flag-suppressed — no echo write")

            page.magnitude = "1.0"
            h.renderer.scheduler.flush()
            for _ in 0..<50 where memory.saves.isEmpty { await Task.yield() }
            #expect(memory.saves.map(\.key) == ["FilterPage.magnitude"])
            #expect(memory.saves.first?.value as? String == "1.0")
        }
    }

    @Test("missing key and wrong-shape value both keep the default, no crash")
    @MainActor
    func missingAndCorruptKeepDefault() async throws {
        try await withMemoryStorage { memory in
            memory.values["FilterPage.magnitude"] = 42   // wrong type → load casts to nil
            let page = FilterPage()
            let h = render(page)
            await page._swiflowHydratePersisted()
            h.renderer.scheduler.flush()
            #expect(h.find("p")?.text == "2.5|day")
        }
    }
}
