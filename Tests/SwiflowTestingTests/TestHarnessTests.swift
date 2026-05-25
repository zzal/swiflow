// Tests/SwiflowTestingTests/TestHarnessTests.swift
import Testing
@testable import SwiflowTesting
import Swiflow

// Minimal inline component used by Task 2–4 tests.
// Expanded to full Counter + SignIn in Task 5.
@MainActor
private final class MinimalCounter: Component {
    @State var count: Int = 0
    @State var label: String = "Swiflow"

    var body: VNode {
        div {
            p("Count: \(count)")
            button("Increment", .on(.click) { self.count += 1 })
            input(.attr("type", "text"),
                  .on(.input) { info in self.label = info.targetValue ?? self.label })
            p("Hello, \(self.label)!")
        }
    }
}

@MainActor
private final class Counter: Component {
    @State var count: Int = 0
    @State var name: String = "Swiflow"
    @State var showToast: Bool = false

    var body: VNode {
        div {
            h1("Hello, \(name)!")
            p("Count: \(count)")
            button("Increment", .on(.click) { self.count += 1 })
            button("Show toast", .on(.click) { self.showToast = true })
            if showToast { div { VNode.text("Saved!") } }
            input(.attr("type", "text"),
                  .on(.input) { info in self.name = info.targetValue ?? self.name })
        }
    }
}

@MainActor
private final class SignIn: Component {
    @State var email: String = ""
    @State var password: String = ""
    @State var emailTouched: Bool = false
    @State var passwordTouched: Bool = false
    @State var isSignedIn: Bool = false

    var emailError: String? {
        guard emailTouched, !email.isEmpty else { return nil }
        return email.contains("@") ? nil : "Invalid email address"
    }

    var passwordError: String? {
        guard passwordTouched, !password.isEmpty else { return nil }
        return password.count >= 8 ? nil : "Must be at least 8 characters"
    }

    var body: VNode {
        div {
            if isSignedIn {
                p("Signed in as \(email)!")
                button("Sign out", .on(.click) {
                    self.isSignedIn = false
                    self.email = ""
                    self.password = ""
                    self.emailTouched = false
                    self.passwordTouched = false
                })
            } else {
                h2("Sign In")
                input(.attr("type", "email"),
                      .on(.input) { info in self.email = info.targetValue ?? self.email },
                      .on(.blur) { self.emailTouched = true })
                if let err = emailError { p(err) }
                input(.attr("type", "password"),
                      .on(.input) { info in self.password = info.targetValue ?? self.password },
                      .on(.blur) { self.passwordTouched = true })
                if let err = passwordError { p(err) }
                button("Sign In", .on(.click) {
                    self.emailTouched = true
                    self.passwordTouched = true
                    guard self.emailError == nil, self.passwordError == nil,
                          !self.email.isEmpty, !self.password.isEmpty else { return }
                    self.isSignedIn = true
                })
            }
        }
    }
}

@Component
private final class PropHost {
    @State var text = "hello"
    var body: VNode {
        input(.prop("value", .string(text)))
    }
}

@MainActor @Component
private final class SelectHost {
    @State var selection = "opt1"

    var body: VNode {
        div {
            select(.on(.change) { info in self.selection = info.targetValue ?? self.selection }) {
                option("Option 1", .attr("value", "opt1"))
                option("Option 2", .attr("value", "opt2"))
            }
            p("Selected: \(selection)")
        }
    }
}

@Suite("TestHarness — allText")
@MainActor
struct AllTextTests {
    @Test("allText includes initial state")
    func allTextInitial() {
        let r = render(MinimalCounter())
        #expect(r.allText.contains("Count: 0"))
    }
}

@Suite("TestHarness — queries")
@MainActor
struct QueryTests {
    @Test("find returns the first matching element with correct fields")
    func findReturnsFirstMatch() {
        let r = render(MinimalCounter())
        let node = r.find("p", text: "Count: 0")
        #expect(node != nil)
        #expect(node?.tag == "p")
        #expect(node?.text == "Count: 0")
    }

    @Test("find returns nil when no match")
    func findReturnsNil() {
        let r = render(MinimalCounter())
        #expect(r.find("p", text: "Count: 99") == nil)
        #expect(r.find("h1") == nil)
    }

    @Test("find without text matches first element with that tag")
    func findByTagOnly() {
        let r = render(MinimalCounter())
        let node = r.find("p")
        #expect(node != nil)
        #expect(node?.tag == "p")
    }

    @Test("findAll returns all matching elements")
    func findAllReturnsAll() {
        let r = render(MinimalCounter())
        let ps = r.findAll("p")
        #expect(ps.count == 2)
        #expect(ps[0].text == "Count: 0")
        #expect(ps[1].text == "Hello, Swiflow!")
    }

    @Test("TestNode.properties is typed [String: String], not [String: PropertyValue]")
    @MainActor
    func testNodePropertiesIsStringDict() {
        let h = render(PropHost())
        let node = h.find("input")
        let props: [String: String]? = node?.properties  // ← type assertion
        #expect(props?["value"] == "hello")
    }

    @Test("exists returns true iff at least one match")
    func existsReturnsTrueAndFalse() {
        let r = render(MinimalCounter())
        #expect(r.exists("p", text: "Count: 0") == true)
        #expect(r.exists("p", text: "Count: 99") == false)
        #expect(r.exists("button") == true)
        #expect(r.exists("h1") == false)
    }
}

@Suite("TestHarness — interactions")
@MainActor
struct InteractionTests {
    @Test("click fires the handler and state updates")
    func clickIncrementsCount() {
        let r = render(MinimalCounter())
        #expect(r.find("p", text: "Count: 0") != nil)
        r.click("button", text: "Increment")
        #expect(r.find("p", text: "Count: 1") != nil)
        #expect(r.find("p", text: "Count: 0") == nil)
    }

    @Test("multiple clicks accumulate")
    func multipleClicks() {
        let r = render(MinimalCounter())
        r.click("button", text: "Increment")
        r.click("button", text: "Increment")
        r.click("button", text: "Increment")
        #expect(r.find("p", text: "Count: 3") != nil)
    }

    @Test("input fires the input handler and state updates")
    func inputUpdatesLabel() {
        let r = render(MinimalCounter())
        #expect(r.find("p", text: "Hello, Swiflow!") != nil)
        r.input(value: "World")
        #expect(r.find("p", text: "Hello, World!") != nil)
        #expect(r.find("p", text: "Hello, Swiflow!") == nil)
    }

    @Test("click is a no-op when no handler is registered")
    func clickNoHandlerIsNoOp() {
        let r = render(MinimalCounter())
        r.click("p")     // <p> has no click handler — must not crash
        #expect(r.find("p", text: "Count: 0") != nil)
    }

    @Test("input at out-of-bounds index is a no-op")
    func inputOutOfBoundsIsNoOp() {
        let r = render(MinimalCounter())
        r.input(at: 99, value: "boom")   // no crash
        #expect(r.find("p", text: "Hello, Swiflow!") != nil)
    }

    @Test("change() dispatches a change event and updates state via the .on(.change) handler")
    func changeUpdatesStateViaOnChangeHandler() {
        let h = render(SelectHost())
        #expect(h.find("p")?.text == "Selected: opt1")
        h.change("select", value: "opt2")
        #expect(h.find("p")?.text == "Selected: opt2")
    }
}

@Suite("Counter — spec test cases")
@MainActor
struct CounterSpecTests {
    @Test("initial state")
    func initialState() {
        let r = render(Counter())
        #expect(r.find("p", text: "Count: 0") != nil)
        #expect(r.find("h1", text: "Hello, Swiflow!") != nil)
    }

    @Test("click increments count")
    func clickIncrements() {
        let r = render(Counter())
        r.click("button", text: "Increment")
        #expect(r.find("p", text: "Count: 1") != nil)
        #expect(r.find("p", text: "Count: 0") == nil)
    }

    @Test("three clicks reach count 3")
    func threeClicks() {
        let r = render(Counter())
        r.click("button", text: "Increment")
        r.click("button", text: "Increment")
        r.click("button", text: "Increment")
        #expect(r.find("p", text: "Count: 3") != nil)
    }

    @Test("conditional toast rendering")
    func toastConditional() {
        let r = render(Counter())
        #expect(r.exists("div", text: "Saved!") == false)
        r.click("button", text: "Show toast")
        #expect(r.exists("div", text: "Saved!"))
    }

    @Test("two-way input binding updates greeting")
    func inputBinding() {
        let r = render(Counter())
        #expect(r.find("h1", text: "Hello, Swiflow!") != nil)
        r.input(value: "World")
        #expect(r.find("h1", text: "Hello, World!") != nil)
    }

    @Test("allText contains all visible text")
    func allTextSmoke() {
        let r = render(Counter())
        #expect(r.allText.contains("Count: 0"))
        #expect(r.allText.contains("Hello, Swiflow!"))
    }

    @Test("findAll returns buttons in document order")
    func findAllButtons() {
        let r = render(Counter())
        let buttons = r.findAll("button")
        #expect(buttons.count >= 2)
        #expect(buttons[0].text == "Increment")
        #expect(buttons[1].text == "Show toast")
    }
}

@Suite("SignIn — form validation spec cases")
@MainActor
struct SignInSpecTests {
    @Test("untouched form shows no errors")
    func untouchedNoErrors() {
        let r = render(SignIn())
        #expect(r.exists("p", text: "Required") == false)
        #expect(r.exists("p", text: "Invalid email") == false)
        #expect(r.exists("p", text: "Must be at least") == false)
    }

    @Test("invalid email after touch shows error")
    func invalidEmailShowsError() {
        let r = render(SignIn())
        r.input(at: 0, value: "notanemail")
        r.blur(at: 0)
        #expect(r.find("p", text: "Invalid email address") != nil)
    }

    @Test("valid email clears email error")
    func validEmailClearsError() {
        let r = render(SignIn())
        r.input(at: 0, value: "notanemail")
        r.blur(at: 0)
        r.input(at: 0, value: "good@test.com")
        r.blur(at: 0)
        #expect(r.find("p", text: "Invalid email address") == nil)
    }

    @Test("short password after touch shows error")
    func shortPasswordShowsError() {
        let r = render(SignIn())
        r.input(at: 1, value: "short")
        r.blur(at: 1)
        #expect(r.find("p", text: "Must be at least 8 characters") != nil)
    }

    @Test("valid password clears password error")
    func validPasswordClearsError() {
        let r = render(SignIn())
        r.input(at: 1, value: "short")
        r.blur(at: 1)
        r.input(at: 1, value: "secret99")
        r.blur(at: 1)
        #expect(r.exists("p", text: "Must be at least") == false)
    }

    @Test("submit with valid credentials signs in")
    func submitSignsIn() {
        let r = render(SignIn())
        r.input(at: 0, value: "good@test.com")
        r.blur(at: 0)
        r.input(at: 1, value: "secret99")
        r.blur(at: 1)
        r.click("button", text: "Sign In")
        #expect(r.find("p", text: "Signed in as good@test.com!") != nil)
    }

    @Test("sign out returns to sign-in form")
    func signOutReturnsToForm() {
        let r = render(SignIn())
        r.input(at: 0, value: "good@test.com")
        r.blur(at: 0)
        r.input(at: 1, value: "secret99")
        r.blur(at: 1)
        r.click("button", text: "Sign In")
        r.click("button", text: "Sign out")
        #expect(r.find("h2", text: "Sign In") != nil)
    }

    @Test("submit with invalid inputs does not sign in")
    func submitInvalidDoesNothing() {
        let r = render(SignIn())
        r.click("button", text: "Sign In")
        #expect(r.find("h2", text: "Sign In") != nil)
        #expect(r.find("p", text: "Signed in as") == nil)
    }
}
