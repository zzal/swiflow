// Tests/SwiflowTestingTests/UncontrolledInputTests.swift
//
// Audit VI Wave-3: the uncontrolled-input targetSnapshot gap. The browser
// driver snapshots the LIVE element.value/checked at event time — typing
// changes them whether or not any render declares them. targetSnapshot used
// to read only the DECLARED properties bag, so on an uncontrolled input a
// blur after type() reported nil where the browser reports the typed text.
// TestRenderer now keeps per-handle DOM-state side-tables: written by
// input/change dispatch (the user typing) and by committed value/checked
// property patches (a render assigning element.value) — the same two writers
// the real DOM has.
import Testing
import Swiflow
@testable import SwiflowTesting

@Component
private final class UncontrolledForm {
    @State var submitted: String = "none"
    var body: VNode {
        div {
            // No .value prop, no state write-back on input: uncontrolled.
            element("input", attributes: [
                .attr("type", "text"),
                .on(.blur) { (e: EventInfo) in self.submitted = e.targetValue ?? "nil" },
            ], children: [])
            p("submitted: \(submitted)")
        }
    }
}

@Component
private final class NormalizingForm {
    @State var code: String = ""
    @State var submitted: String = "none"
    var body: VNode {
        div {
            // Controlled + normalizing: every keystroke re-renders UPPERCASED.
            element("input", attributes: [
                .prop("value", .string(code)),
                .on(.input) { (e: EventInfo) in self.code = (e.targetValue ?? "").uppercased() },
                .on(.blur) { (e: EventInfo) in self.submitted = e.targetValue ?? "nil" },
            ], children: [])
            p("submitted: \(submitted)")
        }
    }
}

@Component
private final class UncontrolledCheckbox {
    @State var submitted: String = "none"
    var body: VNode {
        div {
            element("input", attributes: [
                .attr("type", "checkbox"),
                .on(.change) { _ in },   // uncontrolled: no state write-back
                .on(.custom("focusout")) { (e: EventInfo) in
                    self.submitted = e.targetChecked.map(String.init) ?? "nil"
                },
            ], children: [])
            p("submitted: \(submitted)")
        }
    }
}

@Suite("uncontrolled inputs — event snapshots read live DOM state")
@MainActor
struct UncontrolledInputTests {

    @Test("blur after type() on an UNCONTROLLED input reports the typed value")
    func uncontrolledBlurSeesTypedValue() {
        let h = render(UncontrolledForm())
        h.find("input")!.type("swiflow").blur()
        #expect(h.find("p")?.text == "submitted: swiflow",
                "the browser's element.value holds what was typed even though no render declares it")
    }

    @Test("a render that re-assigns the value property overwrites the typed value")
    func controlledNormalizationWins() {
        let h = render(NormalizingForm())
        h.find("input")!.type("abc").blur()
        #expect(h.find("p")?.text == "submitted: ABC",
                "the normalizing render's value patch is the LAST DOM write, like the browser")
    }

    @Test("an uncontrolled checkbox remembers its toggled state for later events")
    func uncontrolledCheckboxState() {
        let h = render(UncontrolledCheckbox())
        h.check(at: 0, checked: true)
        h.find("input")!.fire("focusout")
        #expect(h.find("p")?.text == "submitted: true",
                "the focusout snapshot carries checked=true from the earlier toggle")
    }
}
