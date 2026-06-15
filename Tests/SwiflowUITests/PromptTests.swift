// Tests/SwiflowUITests/PromptTests.swift
// Prompt is the modal text-input dialog: native <dialog> + an inner <form method="dialog">
// for Enter-to-submit. Host tests cover the structure + the submit/cancel/close wiring
// (deterministic on host); showModal()/focus are verified in the wasm demo build.
import Testing
@testable import Swiflow
@testable import SwiflowUI

@MainActor private func el(_ node: VNode?) -> ElementData? {
    if case .element(let data)? = node { return data }
    return nil
}

@MainActor private func allText(_ node: VNode) -> String {
    switch node {
    case .text(let s):                        return s
    case .element(let d):                     return d.children.map(allText).joined()
    case .fragment(let xs):                   return xs.map(allText).joined()
    case .environmentOverride(_, let child):  return allText(child)
    default:                                  return ""
    }
}

@MainActor private func firstWithClass(_ root: ElementData, _ cls: String) -> ElementData? {
    func walk(_ d: ElementData) -> ElementData? {
        if d.attributes["class"]?.split(separator: " ").map(String.init).contains(cls) == true { return d }
        for c in d.children { if let e = el(c), let hit = walk(e) { return hit } }
        return nil
    }
    return walk(root)
}

@MainActor private func building<T>(_ body: () -> T) -> T {
    let prev = HandlerAmbient.current
    HandlerAmbient.current = HandlerRegistry()
    defer { HandlerAmbient.current = prev }
    return body()
}

@Suite("Prompt")
@MainActor
struct PromptTests {
    private let stayClosed = Binding<Bool>(get: { false }, set: { _ in })
    private let noText = Binding<String>(get: { "" }, set: { _ in })

    private func makePrompt(
        title: String = "Rename file",
        isPresented: Binding<Bool>,
        text: Binding<String>,
        message: String? = "Enter a new name",
        confirm: String = "Rename",
        cancel: String = "Cancel",
        onSubmit: @escaping (String) -> Void = { _ in }
    ) -> PromptDialog {
        PromptDialog(title: title, isPresented: isPresented, text: text, message: message,
                     placeholder: "untitled", confirmTitle: confirm, cancelTitle: cancel, onSubmit: onSubmit)
    }

    @Test("renders a modal <dialog>.sw-dialog.sw-prompt with a form[method=dialog], a TextField, and confirm/cancel") func renders() {
        let d = el(building { makePrompt(isPresented: stayClosed, text: noText).body })!
        #expect(d.tag == "dialog")
        #expect(d.attributes["class"] == "sw-dialog sw-prompt")
        let titleEl = firstWithClass(d, "sw-dialog__title")!
        #expect(titleEl.tag == "h2")
        #expect(d.attributes["aria-labelledby"] == titleEl.attributes["id"])  // named by the <h2>
        let form = firstWithClass(d, "sw-prompt__form")!
        #expect(form.tag == "form")
        #expect(form.attributes["method"] == "dialog")        // submit closes natively, never navigates
        #expect(firstWithClass(form, "sw-field") != nil)      // the input is a SwiflowUI TextField
        #expect(firstWithClass(form, "sw-dialog__actions") != nil)
        #expect(allText(.element(titleEl)) == "Rename file")
    }

    @Test("the message labels the input (implicit TextField <label>); falls back to the title") func fieldLabel() {
        let withMsg = el(building { makePrompt(isPresented: stayClosed, text: noText, message: "Enter a new name").body })!
        #expect(allText(.element(firstWithClass(withMsg, "sw-field__label-text")!)) == "Enter a new name")
        let noMsg = el(building { makePrompt(isPresented: stayClosed, text: noText, message: nil).body })!
        #expect(allText(.element(firstWithClass(noMsg, "sw-field__label-text")!)) == "Rename file")
    }

    @Test("the confirm button is a submit button with NO click handler (the form owns the action)") func confirmIsSubmit() {
        let d = el(building { makePrompt(isPresented: stayClosed, text: noText, confirm: "Save").body })!
        let actions = firstWithClass(d, "sw-dialog__actions")!
        let confirm = el(actions.children[1])!     // [cancel, confirm]
        #expect(confirm.attributes["type"] == "submit")
        #expect(confirm.handlers["click"] == nil)  // no dead handler — submission flows through the form
        #expect(allText(.element(confirm)) == "Save")
    }

    @Test("form submit (Enter or confirm) calls onSubmit with the current text and closes") func submitConfirms() {
        let registry = HandlerRegistry()
        HandlerAmbient.current = registry
        defer { HandlerAmbient.current = nil }
        var submitted: String?
        var presented = true
        var value = "draft-name"
        let d = el(makePrompt(
            isPresented: Binding(get: { presented }, set: { presented = $0 }),
            text: Binding(get: { value }, set: { value = $0 }),
            onSubmit: { submitted = $0 }
        ).body)!
        let form = firstWithClass(d, "sw-prompt__form")!
        // Dispatch with a bogus targetValue: the handler must read the BINDING, not the event payload
        // (on a submit event evt.target is the <form>, which has no value).
        registry.dispatch(id: form.handlers["submit"]!.id, event: EventInfo(type: "submit", targetValue: "WRONG"))
        #expect(submitted == "draft-name")   // onSubmit receives the live binding text, not "WRONG"
        #expect(presented == false)           // and the prompt closes
    }

    @Test("Cancel closes without submitting") func cancelDoesNotSubmit() {
        let registry = HandlerRegistry()
        HandlerAmbient.current = registry
        defer { HandlerAmbient.current = nil }
        var submitted: String?
        var presented = true
        let d = el(makePrompt(
            isPresented: Binding(get: { presented }, set: { presented = $0 }),
            text: noText,
            onSubmit: { submitted = $0 }
        ).body)!
        let cancel = el(firstWithClass(d, "sw-dialog__actions")!.children[0])!  // [cancel, confirm]
        registry.dispatch(id: cancel.handlers["click"]!.id, event: EventInfo(type: "click"))
        #expect(presented == false)
        #expect(submitted == nil)            // cancel never calls onSubmit
    }

    @Test("ESC/native close writes isPresented back to false when open; no-op when already closed") func closeSync() {
        let registry = HandlerRegistry()
        HandlerAmbient.current = registry
        defer { HandlerAmbient.current = nil }
        // open → close event writes false
        var presented = true
        let openD = el(makePrompt(isPresented: Binding(get: { presented }, set: { presented = $0 }), text: noText).body)!
        registry.dispatch(id: openD.handlers["close"]!.id, event: EventInfo(type: "close"))
        #expect(presented == false)
        // already closed → guarded, no redundant write
        var setCount = 0
        let closedD = el(makePrompt(isPresented: Binding(get: { false }, set: { _ in setCount += 1 }), text: noText).body)!
        registry.dispatch(id: closedD.handlers["close"]!.id, event: EventInfo(type: "close"))
        #expect(setCount == 0)
    }

    @Test("the public Prompt(...) free function lowers to an embedded component") func freeFunctionEmbeds() {
        let node = building { Prompt("T", isPresented: stayClosed, text: noText) { _ in } }
        if case .component = node {} else { Issue.record("expected an embedded component node, got \(node)") }
    }

    // MARK: backdrop dismissal (EventInfo.isSelfTarget)

    @Test("content (incl. the form) is wrapped in .sw-dialog__body") func bodyWrapper() {
        let d = el(building { makePrompt(isPresented: stayClosed, text: noText).body })!
        let body = firstWithClass(d, "sw-dialog__body")!
        #expect(body.tag == "div")
        #expect(firstWithClass(body, "sw-prompt__form") != nil)
    }

    @Test("dismissOnBackdrop is off by default — no click handler on the dialog") func noBackdropHandlerByDefault() {
        let d = el(building { makePrompt(isPresented: stayClosed, text: noText).body })!
        #expect(d.handlers["click"] == nil)
    }

    @Test("dismissOnBackdrop: a backdrop click cancels (closes, no onSubmit); a content click does not") func backdropCancels() {
        let registry = HandlerRegistry()
        HandlerAmbient.current = registry
        defer { HandlerAmbient.current = nil }
        var submitted: String?
        var presented = true
        let d = el(PromptDialog(
            title: "Rename", isPresented: Binding(get: { presented }, set: { presented = $0 }),
            text: noText, message: "New name", placeholder: "", confirmTitle: "OK",
            cancelTitle: "Cancel", dismissOnBackdrop: true, onSubmit: { submitted = $0 }
        ).body)!
        registry.dispatch(id: d.handlers["click"]!.id, event: EventInfo(type: "click", isSelfTarget: false))
        #expect(presented == true)   // content click → stays open
        registry.dispatch(id: d.handlers["click"]!.id, event: EventInfo(type: "click", isSelfTarget: true))
        #expect(presented == false)  // backdrop click → cancels
        #expect(submitted == nil)    // …and never calls onSubmit
    }

    @Test("prompt stylesheet stacks the field above the actions, token-driven") func stylesheet() {
        let css = promptStyleSheet.cssString(scopeClass: "")
        #expect(css.contains(".sw-prompt__form"))
        #expect(css.contains("flex-direction: column"))
        #expect(css.contains("var(--sw-space-md)"))
    }
}
