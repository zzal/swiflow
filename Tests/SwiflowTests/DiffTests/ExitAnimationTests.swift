import Testing
@testable import Swiflow

@MainActor
private final class Toaster: Component {
    static var exitAnimation: String? = "fade-out 0.3s ease forwards"
    static var exitDuration: Double? = 0.3
    var body: VNode { div(.class("toast")) {} }
}

@MainActor
private final class Plain: Component {
    var body: VNode { div {} }
}

@Suite("Diff — exit animation")
@MainActor
struct ExitAnimationTests {

    @Test("removing a component with exitAnimation emits animateExit")
    func exitAnimationPatches() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        var result = diff(
            mounted: nil,
            next: .element(ElementData(tag: "div", children: [
                .component(ComponentDescription(Toaster.self, factory: { Toaster() })),
                .component(ComponentDescription(Toaster.self, factory: { Toaster() })),
            ])),
            handles: handles,
            handlers: handlers
        )
        result = diff(
            mounted: result.newMountTree,
            next: .element(ElementData(tag: "div", children: [
                .component(ComponentDescription(Toaster.self, factory: { Toaster() })),
            ])),
            handles: handles,
            handlers: handlers
        )
        let hasAnimateExit = result.patches.contains {
            if case .animateExit(_, _, let anim, _) = $0 {
                return anim == "fade-out 0.3s ease forwards"
            }
            return false
        }
        #expect(hasAnimateExit)
    }

    @Test("removing a component with exitAnimation does NOT emit removeChild for the exiting handle")
    func noRemoveChildForExiting() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        var result = diff(
            mounted: nil,
            next: .element(ElementData(tag: "div", children: [
                .component(ComponentDescription(Toaster.self, factory: { Toaster() })),
            ])),
            handles: handles,
            handlers: handlers
        )
        let toasterDomHandle = result.newMountTree.children.first!.domHandle
        result = diff(
            mounted: result.newMountTree,
            next: .element(ElementData(tag: "div", children: [])),
            handles: handles,
            handlers: handlers
        )
        let hasRemoveChildForToaster = result.patches.contains {
            if case .removeChild(_, let child) = $0 { return child == toasterDomHandle }
            return false
        }
        #expect(!hasRemoveChildForToaster)
    }

    @Test("removing a component WITHOUT exitAnimation still emits removeChild")
    func plainComponentRemovesNormally() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        var result = diff(
            mounted: nil,
            next: .element(ElementData(tag: "div", children: [
                .component(ComponentDescription(Plain.self, factory: { Plain() })),
            ])),
            handles: handles,
            handlers: handlers
        )
        let plainDomHandle = result.newMountTree.children.first!.domHandle
        result = diff(
            mounted: result.newMountTree,
            next: .element(ElementData(tag: "div", children: [])),
            handles: handles,
            handlers: handlers
        )
        let hasRemoveChild = result.patches.contains {
            if case .removeChild(_, let child) = $0 { return child == plainDomHandle }
            return false
        }
        #expect(hasRemoveChild)
    }

    @Test("animateExit durationMs matches exitDuration * 1000")
    func durationMs() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        var result = diff(
            mounted: nil,
            next: .element(ElementData(tag: "div", children: [
                .component(ComponentDescription(Toaster.self, factory: { Toaster() })),
            ])),
            handles: handles,
            handlers: handlers
        )
        result = diff(
            mounted: result.newMountTree,
            next: .element(ElementData(tag: "div", children: [])),
            handles: handles,
            handlers: handlers
        )
        let animPatch = result.patches.first {
            if case .animateExit = $0 { return true }
            return false
        }
        guard case .animateExit(_, _, _, let ms) = animPatch else {
            Issue.record("expected animateExit patch")
            return
        }
        #expect(ms == 300.0)
    }
}
