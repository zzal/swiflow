// Tests/SwiflowTestingTests/RoleQueryTests.swift
//
// Audit VI Wave-2 #1: the find(role:)/find(class:)/find(label:) query
// vocabulary — the RTL getByRole bar. The harness previously queried by
// tag+text only, which is why 27 SwiflowUITests files hand-rolled VNode
// walkers instead of adopting it. Role = explicit `role` attribute, else the
// implicit WAI-ARIA mapping for the tag. Label = aria-label, else an
// associated <label> (`for`-linked or wrapping ancestor), else the element's
// own subtree text — contains-matched, like `text:`.
import Testing
import Swiflow
@testable import SwiflowTesting

@Component
private final class SignUpForm {
    @State var email: String = ""
    var body: VNode {
        div {
            element("h2", attributes: [], children: [text("Create account")])
            element("nav", attributes: [], children: [
                element("a", attributes: [.attr("href", "/login")], children: [text("Log in instead")]),
            ])
            // Wrapping-label pattern (what SwiflowUI's TextField emits).
            element("label", attributes: [], children: [
                element("span", attributes: [], children: [text("Email")]),
                element("input", attributes: [
                    .attr("type", "email"),
                    .on(.input) { (e: EventInfo) in self.email = e.targetValue ?? "" },
                ], children: []),
            ])
            // for-linked label pattern.
            element("label", attributes: [.attr("for", "pw")], children: [text("Password")])
            element("input", attributes: [.attr("id", "pw"), .attr("type", "password")], children: [])
            // aria-label pattern.
            element("input", attributes: [
                .attr("type", "checkbox"), .attr("aria-label", "Accept terms"),
            ], children: [])
            button("Sign up", .on(.click) {})
            // Explicit role overrides the implicit mapping.
            element("div", attributes: [.attr("role", "alert"), .attr("class", "sw-error sw-error--hot")],
                    children: [text("Something failed")])
        }
    }
}

@Suite("find(role:) / find(class:) / find(label:) query vocabulary")
@MainActor
struct RoleQueryTests {

    @Test("implicit roles: button, link, heading, textbox, checkbox")
    func implicitRoles() {
        let h = render(SignUpForm())
        #expect(h.find(role: "button")?.text == "Sign up")
        #expect(h.find(role: "link")?.text == "Log in instead")
        #expect(h.find(role: "heading")?.text == "Create account")
        #expect(h.findAll(role: "textbox").count == 2, "email + password inputs")
        #expect(h.find(role: "checkbox") != nil)
    }

    @Test("an explicit role attribute overrides the implicit mapping")
    func explicitRoleWins() {
        let h = render(SignUpForm())
        let alert = h.find(role: "alert")
        #expect(alert?.text == "Something failed")
        #expect(h.find(role: "navigation") != nil, "implicit landmark still resolves")
    }

    @Test("label: wrapping <label> resolves (the SwiflowUI TextField pattern)")
    func wrappingLabel() {
        let h = render(SignUpForm())
        let email = h.find(role: "textbox", label: "Email")
        #expect(email != nil)
        #expect(email?.attributes["type"] == "email")
    }

    @Test("label: <label for=id> resolves")
    func forLinkedLabel() {
        let h = render(SignUpForm())
        let pw = h.find(role: "textbox", label: "Password")
        #expect(pw?.attributes["type"] == "password")
    }

    @Test("label: aria-label resolves and wins over other sources")
    func ariaLabel() {
        let h = render(SignUpForm())
        #expect(h.find(role: "checkbox", label: "Accept terms") != nil)
        #expect(h.find(label: "Accept terms") != nil, "role-less label query")
    }

    @Test("label: a button's own text is its accessible name")
    func buttonOwnText() {
        let h = render(SignUpForm())
        #expect(h.find(role: "button", label: "Sign up") != nil)
    }

    @Test("find(class:) token-matches the class list")
    func classQuery() {
        let h = render(SignUpForm())
        #expect(h.find(class: "sw-error") != nil)
        #expect(h.find(class: "sw-error--hot") != nil)
        #expect(h.find(class: "sw-err") == nil, "token match, not substring")
    }

    @Test("no match returns nil, mismatched label returns nil")
    func misses() {
        let h = render(SignUpForm())
        #expect(h.find(role: "slider") == nil)
        #expect(h.find(role: "button", label: "Delete") == nil)
    }
}
