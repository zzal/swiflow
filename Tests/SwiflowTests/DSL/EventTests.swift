// Tests/SwiflowTests/DSL/EventTests.swift
import Testing
@testable import Swiflow

@Suite("Event enum")
struct EventTests {
    @Test("Simple cases map to their DOM names", arguments: [
        (Event.click, "click"),
        (Event.input, "input"),
        (Event.change, "change"),
        (Event.submit, "submit"),
        (Event.keydown, "keydown"),
        (Event.keyup, "keyup"),
        (Event.keypress, "keypress"),
        (Event.focus, "focus"),
        (Event.blur, "blur"),
        (Event.mousedown, "mousedown"),
        (Event.mouseup, "mouseup"),
        (Event.mousemove, "mousemove"),
        (Event.mouseenter, "mouseenter"),
        (Event.mouseleave, "mouseleave"),
    ])
    func simpleCases(event: Event, domName: String) {
        #expect(event.domName == domName)
    }

    @Test("Custom event uses the provided name verbatim", arguments: [
        "animationend",
        "my-app:foo",
    ])
    func customEvent(name: String) {
        #expect(Event.custom(name).domName == name)
    }

    @Test("Events are hashable and equatable")
    func hashableEquatable() {
        #expect(Event.click == Event.click)
        #expect(Event.click != Event.input)
        #expect(Event.custom("x") == Event.custom("x"))
        #expect(Event.custom("x") != Event.custom("y"))
        let set: Set<Event> = [.click, .input, .custom("foo")]
        #expect(set.count == 3)
    }
}
