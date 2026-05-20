// Tests/SwiflowTests/DSL/EventTests.swift
import Testing
@testable import Swiflow

@Suite("Event enum")
struct EventTests {
    @Test("Simple cases map to their DOM names")
    func simpleCases() {
        #expect(Event.click.domName == "click")
        #expect(Event.input.domName == "input")
        #expect(Event.change.domName == "change")
        #expect(Event.submit.domName == "submit")
        #expect(Event.keydown.domName == "keydown")
        #expect(Event.keyup.domName == "keyup")
        #expect(Event.keypress.domName == "keypress")
        #expect(Event.focus.domName == "focus")
        #expect(Event.blur.domName == "blur")
        #expect(Event.mousedown.domName == "mousedown")
        #expect(Event.mouseup.domName == "mouseup")
        #expect(Event.mousemove.domName == "mousemove")
        #expect(Event.mouseenter.domName == "mouseenter")
        #expect(Event.mouseleave.domName == "mouseleave")
    }

    @Test("Custom event uses the provided name verbatim")
    func customEvent() {
        #expect(Event.custom("animationend").domName == "animationend")
        #expect(Event.custom("my-app:foo").domName == "my-app:foo")
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
