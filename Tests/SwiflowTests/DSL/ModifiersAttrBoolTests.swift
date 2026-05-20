import Testing
@testable import Swiflow

@Suite("attr(_:_:Bool) — boolean attribute semantics")
struct AttrBoolTests {

    @Test("prefix .attr writes presence-only string when true")
    func prefixTrueEmits() {
        let node = button("Save", .attr("disabled", true))
        guard case .element(let data) = node else {
            Issue.record("expected element"); return
        }
        #expect(data.attributes["disabled"] == "")
    }

    @Test("prefix .attr omits attribute when false")
    func prefixFalseOmits() {
        let node = button("Save", .attr("disabled", false))
        guard case .element(let data) = node else {
            Issue.record("expected element"); return
        }
        #expect(data.attributes["disabled"] == nil)
    }

    @Test("postfix .attr writes presence-only string when true")
    func postfixTrueEmits() {
        let node = button("Save").attr("disabled", true)
        guard case .element(let data) = node else {
            Issue.record("expected element"); return
        }
        #expect(data.attributes["disabled"] == "")
    }

    @Test("postfix .attr omits attribute when false")
    func postfixFalseOmits() {
        let node = button("Save").attr("disabled", false)
        guard case .element(let data) = node else {
            Issue.record("expected element"); return
        }
        #expect(data.attributes["disabled"] == nil)
    }
}
