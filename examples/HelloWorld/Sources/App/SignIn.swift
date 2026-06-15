// Sources/App/SignIn.swift
import Swiflow
import SwiflowUI

/// SignIn — a form-validation demo, hosted inside Counter's <dialog>. Dogfoods
/// SwiflowUI: `TextField(field:)` for the labelled, validated fields (label + input
/// + role=alert error + aria-invalid, with blur→markTouched wired) and `Button` for
/// the actions, laid out with `VStack`/`HStack`. No hand-rolled field/button chrome
/// or per-component CSS — it all comes from SwiflowUI's token-driven sheets.
@MainActor @Component
final class SignIn {
    @State var email: String    = ""
    @State var password: String = ""
    @State var ctrl: FormController = FormController()
    @State var submitted: Bool  = false
    let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    var body: VNode {
        let em = Field("email",    $email,    $ctrl, .required(), .email)
        let pw = Field("password", $password, $ctrl, .required(), .minLength(8),
                       .custom("Must contain a number") { $0.contains { $0.isNumber } })
        let form = Form($ctrl) { em; pw }

        return VStack(spacing: .md, align: .stretch) {
            if submitted {
                p("Signed in as \(email)!")
                HStack(spacing: .sm) {
                    Button("Sign out", variant: .secondary) {
                        self.submitted = false
                        self.email = ""
                        self.password = ""
                        self.ctrl = FormController()
                    }
                    Button("Close") { self.onClose() }
                }
            } else {
                h2("Sign In")
                TextField("Email", field: em, type: .email)
                TextField("Password", field: pw, type: .password)
                HStack(spacing: .sm) {
                    Button("Sign In", disabled: !form.isValid) {
                        form.touchAll()
                        guard form.isValid else { return }
                        self.submitted = true
                    }
                    Button("Reset", variant: .secondary) { form.reset() }
                    Button("Cancel", variant: .secondary) { self.onClose() }
                }
            }
        }
        .padding(.lg)   // the dialog has padding:0; the content pads itself
    }
}
