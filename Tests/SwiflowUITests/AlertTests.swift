// Tests/SwiflowUITests/AlertTests.swift
// Alert is the first STATEFUL overlay (@Component). The modal showModal()/close()
// sync is imperative JS (no-ops on host, where Ref.wrappedValue is nil), so these
// host tests cover what's deterministic on host: the dialog *structure* and the
// native `close` → `isPresented` write-back. The open/close animation + focus trap
// are verified in the WASM demo build.
import Testing
@testable import Swiflow      // HandlerAmbient / HandlerRegistry / EventInfo for the close handler
@testable import SwiflowUI    // AlertDialog (the internal @Component behind the Alert free fn)

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

@Suite("Alert")
@MainActor
struct AlertTests {
    private let dismissed = Binding<Bool>(get: { false }, set: { _ in })

    @Test("renders a modal <dialog>.sw-alert: alertdialog role, accessible name, title, message, actions") func renders() {
        let node = building {
            AlertDialog(title: "Delete this item?", isPresented: dismissed, message: "This can't be undone.") {
                [Button("Cancel", variant: .secondary) {}, Button("Delete") {}]
            }.body
        }
        let d = el(node)!
        #expect(d.tag == "dialog")
        #expect(d.attributes["class"] == "sw-alert")
        #expect(d.attributes["role"] == "alertdialog")     // alert (requires a response), not a plain dialog
        let titleEl = firstWithClass(d, "sw-alert__title")!
        let msgEl = firstWithClass(d, "sw-alert__message")!
        #expect(titleEl.tag == "h2")
        #expect(msgEl.tag == "p")
        // accessible name = the visible <h2>; description = the message <p> (id-associated, not aria-label)
        #expect(d.attributes["aria-label"] == nil)
        #expect(d.attributes["aria-labelledby"] == titleEl.attributes["id"])
        #expect(titleEl.attributes["id"] != nil)
        #expect(d.attributes["aria-describedby"] == msgEl.attributes["id"])
        #expect(msgEl.attributes["id"] != nil)
        #expect(firstWithClass(d, "sw-alert__actions") != nil)
        #expect(allText(node).contains("Delete this item?"))
        #expect(allText(node).contains("This can't be undone."))
        #expect(allText(node).contains("Cancel"))
        #expect(allText(node).contains("Delete"))
    }

    @Test("message is optional — omitting it drops the paragraph and the aria-describedby") func noMessage() {
        let d = el(building { AlertDialog(title: "Heads up", isPresented: dismissed, message: nil) { [Button("OK") {}] }.body })!
        #expect(firstWithClass(d, "sw-alert__message") == nil)
        #expect(d.attributes["aria-describedby"] == nil)     // no message → nothing to describe
        #expect(d.attributes["aria-labelledby"] != nil)      // title still names it
        #expect(firstWithClass(d, "sw-alert__title") != nil)
    }

    @Test("the native close event (incl. ESC) writes isPresented back to false when open") func closeWritesBinding() {
        let registry = HandlerRegistry()
        HandlerAmbient.current = registry
        defer { HandlerAmbient.current = nil }
        var presented = true
        let binding = Binding<Bool>(get: { presented }, set: { presented = $0 })
        let d = el(AlertDialog(title: "T", isPresented: binding) { [text("x")] }.body)!
        registry.dispatch(id: d.handlers["close"]!.id, event: EventInfo(type: "close"))
        #expect(presented == false)
    }

    @Test("close handler is a no-op when already closed — no redundant binding write (no wasted render)") func closeGuardWhenClosed() {
        let registry = HandlerRegistry()
        HandlerAmbient.current = registry
        defer { HandlerAmbient.current = nil }
        var setCount = 0
        let binding = Binding<Bool>(get: { false }, set: { _ in setCount += 1 })
        let d = el(AlertDialog(title: "T", isPresented: binding) { [text("x")] }.body)!
        registry.dispatch(id: d.handlers["close"]!.id, event: EventInfo(type: "close"))
        #expect(setCount == 0)   // already false → the guard skips the write
    }

    @Test("onAppear/onChange with isPresented=true at mount is a safe no-op on host (ref unresolved)") func mountWhilePresentedDoesNotTrap() {
        // On host Ref.wrappedValue is nil, so syncOpenState must early-return rather than
        // trap when an alert is constructed already-presented. (showModal itself is WASM-only.)
        let alert = AlertDialog(title: "T", isPresented: Binding<Bool>(get: { true }, set: { _ in })) { [text("x")] }
        _ = building { alert.body }
        alert.onAppear()
        alert.onChange()
    }

    @Test("the public Alert(...) free function lowers to an embedded component, not a raw element") func freeFunctionEmbeds() {
        let node = building { Alert("T", isPresented: dismissed) { text("x") } }
        if case .component = node {} else { Issue.record("expected an embedded component node, got \(node)") }
    }

    @Test("stylesheet: modal backdrop + @starting-style entry, every value token-driven") func stylesheet() {
        let css = alertStyleSheet.cssString(scopeClass: "")
        #expect(css.contains(".sw-alert"))
        #expect(css.contains("min-width: 30ch"))
        #expect(css.contains(".sw-alert[open]"))
        #expect(css.contains(".sw-alert::backdrop"))
        #expect(css.contains("@starting-style"))
        #expect(css.contains("var(--sw-overlay-bg)"))   // M2 overlay token → reduced-transparency solidifies it
        #expect(css.contains("var(--sw-backdrop)"))
        #expect(css.contains("var(--sw-duration)"))      // → reduced-motion collapses the animation
        #expect(css.contains("allow-discrete"))          // dialog stays painted through the exit transition
        #expect(css.contains("var(--sw-shadow)"))
    }
}
