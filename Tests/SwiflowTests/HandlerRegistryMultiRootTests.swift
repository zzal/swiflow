import Testing
import Swiflow

@Suite("HandlerRegistry multi-root", .serialized)
struct HandlerRegistryMultiRootTests {

    @Test("Two registries produce non-overlapping handler IDs")
    func nonOverlappingIDs() {
        let a = HandlerRegistry()
        let b = HandlerRegistry()
        let ha = a.register { _ in }
        let hb = b.register { _ in }
        #expect(ha.id != hb.id)
    }

    @Test("dispatchGlobal fires handler registered in registry A")
    func dispatchGlobalRegistryA() {
        let a = HandlerRegistry()
        var fired = false
        let h = a.register { _ in fired = true }
        HandlerRegistry.dispatchGlobal(id: h.id, event: EventInfo(type: "click"))
        #expect(fired)
    }

    @Test("dispatchGlobal fires handler registered in registry B")
    func dispatchGlobalRegistryB() {
        let b = HandlerRegistry()
        var fired = false
        let h = b.register { _ in fired = true }
        HandlerRegistry.dispatchGlobal(id: h.id, event: EventInfo(type: "click"))
        #expect(fired)
    }

    @Test("deinit sweeps handlers from globalTable; surviving registry still dispatches")
    func deinitSweepsGlobalTable() {
        let b = HandlerRegistry()
        var bFired = false
        let hb = b.register { _ in bFired = true }

        var aFired = false
        let aID: Int
        do {
            let a = HandlerRegistry()
            let ha = a.register { _ in aFired = true }
            aID = ha.id
        } // a is deallocated here; deinit must sweep aID from globalTable

        // A's handler was swept — dispatching its ID must not fire the closure.
        HandlerRegistry.dispatchGlobal(id: aID, event: EventInfo(type: "click"))
        #expect(!aFired)

        // B is unaffected and still dispatches.
        HandlerRegistry.dispatchGlobal(id: hb.id, event: EventInfo(type: "click"))
        #expect(bFired)
    }
}
