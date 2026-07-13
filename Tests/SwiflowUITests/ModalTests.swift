// Tests/SwiflowUITests/ModalTests.swift
// Modal is the general-purpose sibling of Alert/Prompt: same native <dialog>.showModal()
// modal machinery (ModalDialogHost), but no baked-in role/title-required/actions-slot
// opinion — just an optional title, a size variant, and caller content. These host tests
// cover the deterministic dialog *structure*; the open/close animation + focus trap are
// verified in the WASM demo build (see Alert/PromptTests for the same split).
import Testing
@testable import Swiflow      // HandlerAmbient / HandlerRegistry / EventInfo for the close handler
@testable import SwiflowUI    // ModalDialog (the internal @Component behind the Modal free fn)

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

@Suite("Modal")
@MainActor
struct ModalTests {
    private let dismissed = Binding<Bool>(get: { false }, set: { _ in })

    @Test("renders a modal <dialog>.sw-modal--md (the chrome default size), no role") func renders() {
        let node = building {
            ModalDialog(isPresented: dismissed, title: "Settings", size: .md, dismissOnBackdrop: true) {
                [text("body content")]
            }.body
        }
        let d = el(node)!
        #expect(d.tag == "dialog")
        #expect(d.attributes["class"] == "sw-dialog sw-modal sw-modal--md")
        #expect(d.attributes["role"] == nil)   // native dialog role — unlike Alert's alertdialog
        #expect(allText(node).contains("body content"))
    }

    @Test("size variants land in the modifier class") func sizeVariants() {
        let sm = el(building { ModalDialog(isPresented: dismissed, size: .sm) { [text("x")] }.body })!
        #expect(sm.attributes["class"] == "sw-dialog sw-modal sw-modal--sm")
        let lg = el(building { ModalDialog(isPresented: dismissed, size: .lg) { [text("x")] }.body })!
        #expect(lg.attributes["class"] == "sw-dialog sw-modal sw-modal--lg")
    }

    @Test("optional title renders an h2 with aria-labelledby wired to its id") func withTitle() {
        let d = el(building { ModalDialog(isPresented: dismissed, title: "Settings") { [text("x")] }.body })!
        let titleEl = firstWithClass(d, "sw-dialog__title")!
        #expect(titleEl.tag == "h2")
        #expect(titleEl.attributes["id"] != nil)
        #expect(d.attributes["aria-labelledby"] == titleEl.attributes["id"])
        #expect(allText(.element(d)).contains("Settings"))
    }

    @Test("no title — no h2, no aria-labelledby") func noTitle() {
        let d = el(building { ModalDialog(isPresented: dismissed, title: nil) { [text("x")] }.body })!
        #expect(firstWithClass(d, "sw-dialog__title") == nil)
        #expect(d.attributes["aria-labelledby"] == nil)
    }

    @Test("caller content lands inside .sw-dialog__body, after the title when present") func bodyWrapper() {
        let d = el(building { ModalDialog(isPresented: dismissed, title: "Settings") { [text("caller content")] }.body })!
        let body = firstWithClass(d, "sw-dialog__body")!
        #expect(body.tag == "div")
        #expect(firstWithClass(body, "sw-dialog__title") != nil)
        // title precedes content: first child is the h2, content follows
        #expect(el(body.children.first!)?.tag == "h2")
        #expect(allText(.element(body)).contains("caller content"))
    }

    @Test("a close handler is registered (native close, incl. ESC, writes isPresented back)") func closeHandler() {
        let registry = HandlerRegistry()
        HandlerAmbient.current = registry
        defer { HandlerAmbient.current = nil }
        var presented = true
        let binding = Binding<Bool>(get: { presented }, set: { presented = $0 })
        let d = el(ModalDialog(isPresented: binding) { [text("x")] }.body)!
        #expect(d.handlers["close"] != nil)
        registry.dispatch(id: d.handlers["close"]!.id, event: EventInfo(type: "close"))
        #expect(presented == false)
    }

    @Test("dismissOnBackdrop: true (the default) registers a click handler") func backdropDefaultOn() {
        let d = el(building { ModalDialog(isPresented: dismissed) { [text("x")] }.body })!
        #expect(d.handlers["click"] != nil)
    }

    @Test("dismissOnBackdrop: false registers no click handler") func backdropOff() {
        let d = el(building { ModalDialog(isPresented: dismissed, dismissOnBackdrop: false) { [text("x")] }.body })!
        #expect(d.handlers["click"] == nil)
    }

    @Test("the public Modal(...) free function lowers to an embedded component, not a raw element") func freeFunctionEmbeds() {
        let node = building { Modal(isPresented: dismissed) { text("x") } }
        if case .component = node {} else { Issue.record("expected an embedded component node, got \(node)") }
    }
}
