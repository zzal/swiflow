import Testing
@testable import Swiflow

@Suite("EventInfo typed accessors")
struct EventInfoAccessorsTests {

    @Test("targetChecked defaults to nil")
    func defaultChecked() {
        let e = EventInfo(type: "click")
        #expect(e.targetChecked == nil)
    }

    @Test("targetChecked roundtrips when set")
    func checkedRoundtrip() {
        let e = EventInfo(type: "change", targetChecked: true)
        #expect(e.targetChecked == true)
    }

    @Test("targetChecked false roundtrips")
    func checkedFalseRoundtrip() {
        let e = EventInfo(type: "change", targetChecked: false)
        #expect(e.targetChecked == false)
    }

    @Test("targetIntValue parses a numeric string")
    func intParses() {
        let e = EventInfo(type: "input", targetValue: "42")
        #expect(e.targetIntValue == 42)
    }

    @Test("targetIntValue returns nil for non-numeric targetValue")
    func intNilOnAlpha() {
        let e = EventInfo(type: "input", targetValue: "abc")
        #expect(e.targetIntValue == nil)
    }

    @Test("targetIntValue returns nil when targetValue is nil")
    func intNilOnMissing() {
        let e = EventInfo(type: "input")
        #expect(e.targetIntValue == nil)
    }

    @Test("targetDoubleValue parses a decimal string")
    func doubleParses() {
        let e = EventInfo(type: "input", targetValue: "3.14")
        #expect(e.targetDoubleValue == 3.14)
    }

    @Test("targetDoubleValue returns nil for non-numeric")
    func doubleNilOnAlpha() {
        let e = EventInfo(type: "input", targetValue: "xx")
        #expect(e.targetDoubleValue == nil)
    }

    @Test("isSelfTarget defaults to false")
    func selfTargetDefault() {
        #expect(EventInfo(type: "click").isSelfTarget == false)
    }

    @Test("isSelfTarget roundtrips when set")
    func selfTargetRoundtrip() {
        #expect(EventInfo(type: "click", isSelfTarget: true).isSelfTarget == true)
    }

    @Test("key defaults to nil (non-keyboard events)")
    func keyDefault() {
        #expect(EventInfo(type: "click").key == nil)
    }

    @Test("key roundtrips when set")
    func keyRoundtrip() {
        #expect(EventInfo(type: "keydown", key: "ArrowDown").key == "ArrowDown")
    }

    @Test("modifier flags default to false")
    func modifiersDefault() {
        let e = EventInfo(type: "keydown", key: "Enter")
        #expect(e.shiftKey == false)
        #expect(e.ctrlKey == false)
        #expect(e.altKey == false)
        #expect(e.metaKey == false)
    }

    @Test("modifier flags roundtrip independently")
    func modifiersRoundtrip() {
        let e = EventInfo(type: "keydown", key: "Enter", shiftKey: true, metaKey: true)
        #expect(e.shiftKey == true)
        #expect(e.metaKey == true)
        #expect(e.ctrlKey == false)   // unset stays false
        #expect(e.altKey == false)
    }

    @Test("modifiers are carried on mouse events too (Cmd+click)")
    func modifiersOnClick() {
        let e = EventInfo(type: "click", metaKey: true)
        #expect(e.metaKey == true)
        #expect(e.key == nil)         // a click has no key
    }
}
