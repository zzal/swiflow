// Tests/SwiflowUITests/ToastTests.swift
// Toast is the app-owned-queue overlay: ToastStack renders a Binding<[ToastItem]>,
// each as a keyed ToastView (@Component) that auto-dismisses via after()/TimerHandle.
// The timer is WASM-runtime, so host tests cover structure + the ✕/onDismiss wiring +
// the stack's keyed-embed shape; the timer + slide animation are demo-verified.
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

@Suite("Toast")
@MainActor
struct ToastTests {

    // MARK: ToastItem / variants

    @Test("ToastItem auto-assigns a unique, stable id and stores its fields") func itemIdentity() {
        let a = ToastItem("Saved", variant: .success, duration: 6)
        let b = ToastItem("Saved", variant: .success)
        #expect(a.id != b.id)               // distinct instances → distinct ids (keying)
        #expect(a.message == "Saved")
        #expect(a.variant == .success)
        #expect(a.duration == 6)
        #expect(b.duration == 4)            // default
    }

    @Test("danger is assertive (role=alert); info/success are polite (role=status)") func variantPoliteness() {
        let danger = el(building { ToastView(item: ToastItem("Boom", variant: .danger), recurrences: { 1 }, onDismiss: {}).body })!
        #expect(danger.attributes["role"] == "alert")
        #expect(danger.attributes["aria-live"] == "assertive")
        let info = el(building { ToastView(item: ToastItem("FYI"), recurrences: { 1 }, onDismiss: {}).body })!
        #expect(info.attributes["role"] == "status")
        #expect(info.attributes["aria-live"] == "polite")
    }

    // MARK: ToastView structure + dismiss

    @Test("ToastView renders a variant card with the message and a labelled ✕ close button") func viewStructure() {
        let v = el(building { ToastView(item: ToastItem("File uploaded", variant: .success), recurrences: { 1 }, onDismiss: {}).body })!
        #expect(v.attributes["class"] == "sw-toast sw-toast--success")
        #expect(allText(firstWithClass(v, "sw-toast__message").map { VNode.element($0) } ?? .text("")) == "File uploaded")
        let close = firstWithClass(v, "sw-toast__close")!
        #expect(close.tag == "button")
        #expect(close.attributes["type"] == "button")
        #expect(close.attributes["aria-label"] == "Dismiss")
    }

    @Test("the ✕ button fires onDismiss") func closeDismisses() {
        let registry = HandlerRegistry()
        HandlerAmbient.current = registry
        defer { HandlerAmbient.current = nil }
        var dismissed = false
        let v = el(ToastView(item: ToastItem("x"), recurrences: { 1 }, onDismiss: { dismissed = true }).body)!
        let close = firstWithClass(v, "sw-toast__close")!
        registry.dispatch(id: close.handlers["click"]!.id, event: EventInfo(type: "click"))
        #expect(dismissed)
    }

    @Test("auto-dismiss pauses on hover + focus (WCAG 2.2.1) — pause/resume handlers wired") func pauseHandlers() {
        let v = el(building { ToastView(item: ToastItem("x"), recurrences: { 1 }, onDismiss: {}).body })!
        #expect(v.handlers["mouseenter"] != nil)   // pause on pointer over
        #expect(v.handlers["mouseleave"] != nil)
        #expect(v.handlers["focusin"] != nil)       // pause while focus is within (keyboard)
        #expect(v.handlers["focusout"] != nil)
    }

    // MARK: ToastStack

    @Test("ToastStack renders the placement region with one keyed component per item") func stackRenders() {
        let items = [ToastItem("one"), ToastItem("two"), ToastItem("three")]
        let region = el(building { ToastStack(toasts: Binding(get: { items }, set: { _ in }), placement: .bottomTrailing) })!
        #expect(region.attributes["class"] == "sw-toast-stack sw-toast-stack--bottom-trailing")
        #expect(region.children.count == 3)
        // each child is an embedded component (the keyed ToastView), not a raw element
        for child in region.children {
            if case .component = child {} else { Issue.record("expected a component child, got \(child)") }
        }
    }

    @Test("placement maps to the region modifier class; default is bottom-trailing") func placement() {
        let empty = Binding<[ToastItem]>(get: { [] }, set: { _ in })
        #expect(el(building { ToastStack(toasts: empty) })!.attributes["class"] == "sw-toast-stack sw-toast-stack--bottom-trailing")
        #expect(el(building { ToastStack(toasts: empty, placement: .topCenter) })!.attributes["class"] == "sw-toast-stack sw-toast-stack--top-center")
    }

    @Test("an empty queue renders an empty (pointer-events:none) region") func emptyQueue() {
        let region = el(building { ToastStack(toasts: Binding(get: { [] }, set: { _ in })) })!
        #expect(region.children.isEmpty)
    }

    // MARK: queue removal (the dismiss logic, extracted so it's host-testable)

    @Test("removeToast drops the matching item and preserves the others' order") func removeMiddle() {
        var arr = [ToastItem("a"), ToastItem("b"), ToastItem("c")]
        let b = Binding(get: { arr }, set: { arr = $0 })
        removeToast(arr[1].id, from: b)
        #expect(arr.map(\.message) == ["a", "c"])
    }

    @Test("removeToast is idempotent and ignores unknown ids (safe under double-dismiss)") func removeIdempotent() {
        var arr = [ToastItem("a"), ToastItem("b")]
        let b = Binding(get: { arr }, set: { arr = $0 })
        let idA = arr[0].id
        removeToast(idA, from: b)
        removeToast(idA, from: b)        // timer fired AND ✕ clicked → second call is a no-op
        removeToast("not-present", from: b)
        #expect(arr.map(\.message) == ["b"])
    }

    // MARK: stylesheet

    @Test("stylesheet: positioned region, variant edges, token-driven animation") func stylesheet() {
        let css = toastStyleSheet.cssString(scopeClass: "")
        #expect(css.contains(".sw-toast-stack"))
        #expect(css.contains("pointer-events: none"))          // region doesn't block the page
        #expect(css.contains(".sw-toast-stack--bottom-trailing"))
        #expect(css.contains("pointer-events: auto"))          // toasts do
        #expect(css.contains("border-inline-start: 4px solid var(--sw-accent)"))
        #expect(css.contains(".sw-toast--success"))
        #expect(css.contains(".sw-toast--danger"))
        #expect(css.contains("@keyframes sw-toast-in"))
        #expect(css.contains("@keyframes sw-toast-out"))
        #expect(css.contains("animation: sw-toast-in var(--sw-duration)"))   // reduced-motion → 0s → instant
    }

    @Test("warning variant lowers to sw-toast--warning and is polite") func warningVariant() {
        let warn = el(building { ToastView(item: ToastItem("Careful", variant: .warning), recurrences: { 1 }, onDismiss: {}).body })!
        #expect(allText(.element(warn)).contains("Careful"))
        #expect(firstWithClass(warn, "sw-toast--warning") != nil)
        #expect(ToastVariant.warning.isAssertive == false)   // warning is polite, only danger is assertive
    }

    @Test("stylesheet has explicit info + warning border rules") func infoWarningRules() {
        _ = building { ToastView(item: ToastItem("x"), recurrences: { 1 }, onDismiss: {}).body }  // installs the sheet
        let sheet = toastStyleSheet.cssString(scopeClass: "")
        #expect(sheet.contains(".sw-toast--info"))
        #expect(sheet.contains("border-inline-start-color: var(--sw-info)"))
        #expect(sheet.contains(".sw-toast--warning"))
        #expect(sheet.contains("border-inline-start-color: var(--sw-warning)"))
    }
}

@Suite("Toast coalesce badge")
@MainActor
struct ToastCoalesceBadgeTests {
    @Test("ToastItem starts at count 1; dedupKey combines variant + message")
    func itemDefaults() {
        let a = ToastItem("Saved", variant: .success)
        #expect(a.count == 1)
        let b = ToastItem("Saved", variant: .danger)
        #expect(a.dedupKey != b.dedupKey)
        let c = ToastItem("Saved", variant: .success)
        #expect(a.dedupKey == c.dedupKey)
    }

    @Test("ToastView renders ×N badge only when recurrences > 1")
    func badgeVisibility() {
        let one = building { ToastView(item: ToastItem("Hi"), recurrences: { 1 }, onDismiss: {}).body }
        #expect(firstWithClass(el(one)!, "sw-toast__count") == nil)

        let many = building { ToastView(item: ToastItem("Hi"), recurrences: { 3 }, onDismiss: {}).body }
        let badge = firstWithClass(el(many)!, "sw-toast__count")
        #expect(badge != nil)
        #expect(allText(.element(badge!)).contains("3"))
    }
}
