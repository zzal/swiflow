import Swiflow
import SwiflowUI

@Component
final class TextAreaStory {
    @State var bio: String = ""
    @State var feedback: String = ""
    @State var ctrl: FormController = FormController()

    var body: VNode {
        let feedbackField = Field("feedback", $feedback, $ctrl, .required())

        return storyPage("TextArea",
                          blurb: "A multi-line text field: same label/error chrome as TextField, over a native <textarea>.") {
            variantSection("Multi-line input", snippet: """
            TextArea("Bio", text: $bio, rows: 6, placeholder: "Tell us about you…")
            """) {
                Card(variant: .plain) {
                    VStack(spacing: .md, align: .stretch) {
                        TextArea("Bio", text: $bio, rows: 6, placeholder: "Tell us about you…")
                        if !bio.isEmpty { p("\(bio.count) characters") }
                    }
                }
            }
            variantSection("Field-validated", snippet: """
            let feedbackField = Field("feedback", $feedback, $ctrl, .required())
            TextArea("Feedback", field: feedbackField, rows: 4, placeholder: "What should we improve?")
            """) {
                Card(variant: .plain) {
                    VStack(spacing: .md, align: .stretch) {
                        TextArea("Feedback", field: feedbackField, rows: 4, placeholder: "What should we improve?")
                    }
                }
                p("Interact then blur to see the role=alert error and aria-invalid.")
            }
        }
    }
}
