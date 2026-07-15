import Swiflow
import SwiflowUI

@Component
final class TextFieldStory {
    @State var name: String = ""
    @State var email: String = ""
    @State var ctrl: FormController = FormController()

    var body: VNode {
        let emailField = Field("email", $email, $ctrl, .required(), .email)

        return storyPage("TextField",
                          blurb: "A labelled text input over a Binding<String>. The Field(...) overload wires "
                            + "FormController validators — interact then blur to see the role=alert error "
                            + "and aria-invalid.") {
            variantSection("Plain binding", snippet: """
            TextField("Name", text: $name, placeholder: "Ada Lovelace")
            """) {
                Card(variant: .plain) {
                    VStack(spacing: .md, align: .stretch) {
                        TextField("Name", text: $name, placeholder: "Ada Lovelace")
                        if !name.isEmpty { p("Hello, \(name)!") }
                    }
                }
            }
            variantSection("Field-validated", snippet: """
            let emailField = Field("email", $email, $ctrl, .required(), .email)
            TextField("Email", field: emailField, type: .email, placeholder: "you@example.com")
            """) {
                Card(variant: .plain) {
                    TextField("Email", field: emailField, type: .email, placeholder: "you@example.com")
                }
                p("Type something invalid, then blur: the field turns aria-invalid and a "
                  + "role=alert message appears.")
            }
            variantSection("Horizontal layout", snippet: """
            TextField("Name", text: $name, layout: .horizontal)
            """) {
                Card(variant: .plain) {
                    TextField("Name", text: $name, placeholder: "Ada Lovelace", layout: .horizontal)
                }
            }
        }
    }
}
