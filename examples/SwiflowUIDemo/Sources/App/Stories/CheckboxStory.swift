import Swiflow
import SwiflowUI

@Component
final class CheckboxStory {
    @State var accepted: Bool = false
    @State var simple: Bool = true
    @State var ctrl: FormController = FormController()

    var body: VNode {
        let termsField = Field("terms", $accepted, $ctrl, .custom("You must accept the terms") { $0 })

        return storyPage("Checkbox",
                          blurb: "A custom-drawn checkbox (identical pixels in every browser) over a "
                            + "Binding<Bool>. Checkbox is for confirmation — a value submitted with a "
                            + "form; for an immediate on/off setting reach for Toggle instead.") {
            variantSection("Binding", snippet: """
            Checkbox("Email me a receipt", isOn: $simple)
            """) {
                Card(variant: .plain) {
                    Checkbox("Email me a receipt", isOn: $simple)
                }
            }
            variantSection("Field-validated", snippet: """
            let termsField = Field("terms", $accepted, $ctrl, .custom("You must accept the terms") { $0 })
            Checkbox("I accept the terms", field: termsField)
            """) {
                Card(variant: .plain) {
                    Checkbox("I accept the terms", field: termsField)
                }
                p("Check then uncheck (or blur unchecked): the box turns aria-invalid and a "
                  + "role=alert message appears.")
            }
        }
    }
}
