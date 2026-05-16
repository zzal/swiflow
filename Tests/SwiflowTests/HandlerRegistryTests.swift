// Tests/SwiflowTests/HandlerRegistryTests.swift
import Testing
@testable import Swiflow

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
        r.dispatch(id: h.id, event: Event(type: "click"))
        #expect(observed == "click")
    }

    @Test("Dispatch to unknown ID is a no-op")
    func dispatchUnknownIsNoOp() {
        let r = HandlerRegistry()
        r.dispatch(id: 999, event: Event(type: "click"))  // must not crash
    }
}
