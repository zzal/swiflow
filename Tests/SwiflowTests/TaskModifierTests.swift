import Testing
@testable import Swiflow

@MainActor
struct TaskModifierTests {

    @Test func taskBindingsAreExcludedFromEquality() {
        // Two ElementData identical except for taskBindings must compare equal
        // (closures aren't Equatable; taskBindings is out-of-band, like refBindings).
        let a = ElementData(tag: "div")
        var b = ElementData(tag: "div")
        b.taskBindings = [TaskBinding(dependency: nil, body: {})]
        #expect(a == b)
    }

    @Test func taskBindingsDefaultEmpty() {
        #expect(ElementData(tag: "div").taskBindings.isEmpty)
    }
}
