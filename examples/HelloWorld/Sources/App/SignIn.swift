// Sources/App/SignIn.swift
import Swiflow

/// SignIn — Phase 12b form validation demo, now hosted inside Counter's
/// <dialog>. All inline .style(...) calls migrated to SignIn+Styles.swift.
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

        return div(.class("signin")) {
            if submitted {
                p("Signed in as \(email)!", .class("welcome"))
                div(.class("actions")) {
                    button("Sign out", .class("secondary"), .on(.click) {
                        self.submitted = false
                        self.email = ""
                        self.password = ""
                        self.ctrl = FormController()
                    })
                    button("Close", .on(.click) { self.onClose() })
                }
            } else {
                h2("Sign In", .class("title"))

                div(.class("field")) {
                    label("Email", .attr("for", "signin-email"))
                    input(.id("signin-email"),
                          .attr("type", "email"),
                          .value($email),
                          .on(.blur) { em.markTouched() })
                    if em.touched, let err = em.error {
                        p(err, .class("error"))
                    }
                }

                div(.class("field")) {
                    label("Password", .attr("for", "signin-password"))
                    input(.id("signin-password"),
                          .attr("type", "password"),
                          .value($password),
                          .on(.blur) { pw.markTouched() })
                    if pw.touched, let err = pw.error {
                        p(err, .class("error"))
                    }
                }

                div(.class("actions")) {
                    button("Sign In",
                           .attr("disabled", !form.isValid),
                           .on(.click) {
                               form.touchAll()
                               guard form.isValid else { return }
                               self.submitted = true
                           })
                    button("Reset", .class("secondary"), .on(.click) { form.reset() })
                    button("Cancel", .class("secondary"), .on(.click) { self.onClose() })
                }
            }
        }
    }
}
