// Tests/SwiflowUITests/HarnessAdoptionTests.swift
//
// Audit VI Wave-2 dogfood: the FIRST SwiflowUI suite on the SwiflowTesting
// harness (27 files hand-rolled VNode walkers because the harness spoke only
// tag+text). Real SwiflowUI controls, queried by role/label the way a user
// perceives them, actions on the found node. This file is the adoption
// template for migrating the rest.
import Testing
import Swiflow
import SwiflowUI
import SwiflowTesting

@Component
private final class SettingsForm {
    @State var name: String = ""
    @State var submittedName: String = "none"
    @State var notify: Bool = false
    var body: VNode {
        div {
            TextField("Display name", text: $name, onBlur: {
                self.submittedName = self.name
            })
            Checkbox("Email notifications", isOn: $notify)
            p("notify: \(notify ? "on" : "off"), saved: \(submittedName)")
            Button("Save") {}
        }
    }
}

@Suite("SwiflowUI controls through the harness — role/label adoption template")
@MainActor
struct HarnessAdoptionTests {

    @Test("TextField: found by role+label (its wrapping <label>), typed + blurred")
    func textFieldRoundTrip() {
        let h = render(SettingsForm())
        h.find(role: "textbox", label: "Display name")!.type("Alain").blur()
        #expect(h.find(role: "textbox")?.properties["value"] == "Alain",
                "the binding round-tripped")
        #expect(h.find("p")?.text.contains("saved: Alain") == true,
                "onBlur fired with the typed value")
    }

    @Test("Checkbox: found by role+label, toggled through the found node")
    func checkboxToggle() {
        let h = render(SettingsForm())
        let box = h.find(role: "checkbox", label: "Email notifications")
        #expect(box != nil, "the wrapping-label pattern resolves the control")
        box!.check(true)
        #expect(h.find("p")?.text.contains("notify: on") == true)
        box!.check(false)
        #expect(h.find("p")?.text.contains("notify: off") == true)
    }

    @Test("Button: found by role and accessible name")
    func buttonByRole() {
        let h = render(SettingsForm())
        #expect(h.find(role: "button", label: "Save") != nil)
    }
}
