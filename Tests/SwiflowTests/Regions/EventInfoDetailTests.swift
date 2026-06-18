import Testing
@testable import Swiflow

@Suite("EventInfo.detail")
struct EventInfoDetailTests {
    @Test("detail defaults to nil and is omitted from existing call sites")
    func detailDefaultsNil() {
        let e = EventInfo(type: "click")
        #expect(e.detail == nil)
    }

    @Test("detail round-trips through the initializer and participates in equality")
    func detailRoundTrips() {
        let a = EventInfo(type: "sf:event", detail: #"{"kind":"select","id":7}"#)
        let b = EventInfo(type: "sf:event", detail: #"{"kind":"select","id":7}"#)
        let c = EventInfo(type: "sf:event", detail: nil)
        #expect(a.detail == #"{"kind":"select","id":7}"#)
        #expect(a == b)
        #expect(a != c)
    }
}
