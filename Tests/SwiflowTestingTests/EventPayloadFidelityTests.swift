// Tests/SwiflowTestingTests/EventPayloadFidelityTests.swift
import Testing
import Swiflow
import SwiflowTesting

@Component
private final class CheckboxForm {
    @State var agreed: Bool = false
    var body: VNode {
        div {
            input(.attr("type", "checkbox"), .checked($agreed))
            p { VNode.text(agreed ? "agreed" : "not agreed") }
        }
    }
}

@Component
private final class BlurValidator {
    @State var name: String = "ada"
    @State var lastBlurValue: String = "<none>"
    var body: VNode {
        div {
            input(.value($name), .on(.blur) { info in
                self.lastBlurValue = info.targetValue ?? "<nil>"
            })
            p { VNode.text("blur saw: \(lastBlurValue)") }
        }
    }
}

@Suite
@MainActor
struct EventPayloadFidelityTests {

    /// Audit finding (Unit 9 HIGH): EventInfo never carried targetChecked, so
    /// `.checked` bindings were untestable. The driver sends it on every
    /// dispatch with a checkable target.
    @Test("check() carries targetChecked so a .checked binding toggles") func checkTogglesACheckedBinding() {
        let harness = render(CheckboxForm())
        #expect(harness.find("p")?.text == "not agreed")

        harness.check(checked: true)

        #expect(harness.find("p")?.text == "agreed")
    }

    /// Audit finding (Unit 9 HIGH): blur() dispatched with no targetValue,
    /// while the browser always snapshots target.value — validate-on-blur
    /// handlers worked in production and saw nil under test.
    @Test("blur() snapshots the input's current value into targetValue, like the browser") func blurCarriesTheCurrentTargetValue() {
        let harness = render(BlurValidator())

        harness.blur()

        #expect(harness.allText.contains("blur saw: ada"))
    }
}
