// Tests/SwiflowTests/HandlerRegistryTests.swift
import Testing
@testable import Swiflow

@MainActor
@Suite("HandlerRegistry")
struct HandlerRegistryTests {
    @Test("Registering a closure returns a fresh ID")
    func registerReturnsID() {
        let r = HandlerRegistry()
        let h1 = r.register { _ in }
        let h2 = r.register { _ in }
        #expect(h1.id != h2.id)
        #expect(h2.id == h1.id + 1)
    }

    @Test("Lookup returns the registered handler")
    func lookupReturnsHandler() {
        let r = HandlerRegistry()
        let stored = r.register { _ in }
        let found = r.handler(forID: stored.id)
        #expect(found != nil)
        #expect(found?.id == stored.id)
    }

    @Test("Lookup of unknown ID returns nil")
    func lookupUnknownReturnsNil() {
        let r = HandlerRegistry()
        #expect(r.handler(forID: 999) == nil)
    }

    @Test("Remove drops the entry; lookup returns nil afterward")
    func removeDropsEntry() {
        let r = HandlerRegistry()
        let h = r.register { _ in }
        r.remove(id: h.id)
        #expect(r.handler(forID: h.id) == nil)
    }

    @Test("Remove of unknown ID is a no-op")
    func removeUnknownIsNoOp() {
        let r = HandlerRegistry()
        r.remove(id: 12345)  // must not crash
    }

    @Test("Dispatch invokes the registered closure")
    func dispatchInvokesClosure() {
        let r = HandlerRegistry()
        var observed: String?
        let h = r.register { event in observed = event.type }
        r.dispatch(id: h.id, event: EventInfo(type: "click"))
        #expect(observed == "click")
    }

    @Test("Dispatch to unknown ID is a no-op")
    func dispatchUnknownIsNoOp() {
        let r = HandlerRegistry()
        r.dispatch(id: 999, event: EventInfo(type: "click"))  // must not crash
    }

    // MARK: - Two-map sync invariant (insert/evict funnel)
    //
    // A handler lives in both the instance dict (backing `dispatch`) and the
    // static global table (backing `dispatchGlobal`). These pin that every
    // register/evict keeps the two in lockstep — the property the single
    // insert/evict funnel exists to guarantee.

    @Test("register places the handler in BOTH the instance and global maps")
    func registerSyncsBothMaps() {
        let r = HandlerRegistry()
        var hits = 0
        let h = r.register { _ in hits += 1 }
        r.dispatch(id: h.id, event: EventInfo(type: "click"))               // instance map
        HandlerRegistry.dispatchGlobal(id: h.id, event: EventInfo(type: "click"))  // global map
        #expect(hits == 2, "a freshly-registered handler must be reachable via both dispatch paths")
    }

    @Test("remove evicts from BOTH maps")
    func removeSyncsBothMaps() {
        let r = HandlerRegistry()
        var hits = 0
        let h = r.register { _ in hits += 1 }
        r.remove(id: h.id)
        r.dispatch(id: h.id, event: EventInfo(type: "click"))
        HandlerRegistry.dispatchGlobal(id: h.id, event: EventInfo(type: "click"))
        #expect(hits == 0, "remove must drop the handler from both the instance and global maps")
    }

    @Test("closeScope evicts every scoped handler from BOTH maps")
    func closeScopeSyncsBothMaps() {
        let r = HandlerRegistry()
        var hits = 0
        let scope = r.openScope(debugName: "s")
        let h = r.withScope(scope) { r.register { _ in hits += 1 } }
        r.closeScope(scope)
        r.dispatch(id: h.id, event: EventInfo(type: "click"))
        HandlerRegistry.dispatchGlobal(id: h.id, event: EventInfo(type: "click"))
        #expect(hits == 0, "closeScope must evict scoped handlers from both maps")
    }

    @Test("a released registry drops its handlers from the global table (no leak)")
    func deinitEvictsFromGlobalTable() {
        var hits = 0
        var leakedID = -1
        do {
            let r = HandlerRegistry()
            let h = r.register { _ in hits += 1 }  // permanent (no scope)
            leakedID = h.id
            HandlerRegistry.dispatchGlobal(id: leakedID, event: EventInfo(type: "click"))
            #expect(hits == 1, "the handler is live in the global table while its registry exists")
        }  // registry released → deinit must evict from the global table
        hits = 0
        HandlerRegistry.dispatchGlobal(id: leakedID, event: EventInfo(type: "click"))
        #expect(hits == 0, "deinit must drop the released registry's handlers from the global table")
    }
}
