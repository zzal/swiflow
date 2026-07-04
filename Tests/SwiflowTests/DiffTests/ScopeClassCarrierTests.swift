// Tests/SwiflowTests/DiffTests/ScopeClassCarrierTests.swift
//
// The scope class (`.swiflow-<Type>`) is stamped on a component body's root
// ELEMENT. A non-element root (embedded child component, fragment) has no
// attribute to carry it — which silently unscoped the component's
// `scopedStyles` sheet (injected but matching nothing). The fix: when (and
// only when) the component declares `scopedStyles`, such roots get a
// layout-neutral `display: contents` carrier element. These tests pin down
// both sides of that "only when".
import Testing
@testable import Swiflow

@Suite("Diff — scope-class carrier for non-element body roots")
@MainActor
struct ScopeClassCarrierTests {

    final class Inner: Component {
        var body: VNode { .element(ElementData(tag: "span")) }
    }

    /// scopedStyles + embed root → the auto-wrapped carrier.
    final class StyledShell: Component {
        static var scopedStyles: CSSSheet? = css { raw(".x { color: red }") }
        var body: VNode { .component(.init(Inner.self) { Inner() }) }
    }

    /// No scopedStyles + embed root → pass-through (today's DOM shape).
    final class PlainShell: Component {
        var body: VNode { .component(.init(Inner.self) { Inner() }) }
    }

    /// scopedStyles + element root → plain class stamp, no carrier.
    final class ElementShell: Component {
        static var scopedStyles: CSSSheet? = css { raw(".x { color: red }") }
        var body: VNode { .element(ElementData(tag: "section")) }
    }

    private func createdElements(_ patches: [Patch]) -> [(handle: Int, tag: String)] {
        patches.compactMap { p in
            if case .createElement(let handle, let tag) = p { return (handle, tag) }
            return nil
        }
    }

    private func classAttribute(_ patches: [Patch], handle: Int) -> String? {
        for p in patches {
            if case .setAttribute(let h, "class", let value) = p, h == handle { return value }
        }
        return nil
    }

    @Test("Embed-rooted body WITH scopedStyles mounts a display:contents carrier bearing the scope class")
    func styledEmbedRootGetsCarrier() {
        let result = diff(mounted: nil,
                          next: .component(.init(StyledShell.self) { StyledShell() }),
                          handles: HandleAllocator(), handlers: HandlerRegistry())

        let elements = createdElements(result.patches)
        #expect(elements.map(\.tag) == ["div", "span"], "carrier div wraps the embedded child's root")

        let carrier = elements[0].handle
        #expect(classAttribute(result.patches, handle: carrier) == "swiflow-StyledShell")
        let styledContents = result.patches.contains {
            if case .setStyle(carrier, "display", "contents") = $0 { return true }
            return false
        }
        #expect(styledContents, "carrier must be layout-neutral (display: contents)")
    }

    @Test("Embed-rooted body WITHOUT scopedStyles keeps its DOM shape (no carrier)")
    func plainEmbedRootUnchanged() {
        let result = diff(mounted: nil,
                          next: .component(.init(PlainShell.self) { PlainShell() }),
                          handles: HandleAllocator(), handlers: HandlerRegistry())

        #expect(createdElements(result.patches).map(\.tag) == ["span"],
                "no wrapper element may be introduced for components without scopedStyles")
        let anyShellClass = result.patches.contains {
            if case .setAttribute(_, "class", let v) = $0 { return v.contains("swiflow-PlainShell") }
            return false
        }
        #expect(!anyShellClass, "no scope class should be stamped anywhere")
    }

    @Test("Element-rooted body with scopedStyles gets the class stamp, not a carrier")
    func elementRootStampedInPlace() {
        let result = diff(mounted: nil,
                          next: .component(.init(ElementShell.self) { ElementShell() }),
                          handles: HandleAllocator(), handlers: HandlerRegistry())

        let elements = createdElements(result.patches)
        #expect(elements.map(\.tag) == ["section"], "no extra wrapper for element roots")
        #expect(classAttribute(result.patches, handle: elements[0].handle) == "swiflow-ElementShell")
    }

    @Test("Carrier is stable across re-renders (no root replace on update)")
    func carrierStableAcrossUpdates() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let shell = StyledShell()
        let node = VNode.component(.init(StyledShell.self) { shell })

        let r1 = diff(mounted: nil, next: node, handles: handles, handlers: handlers)
        let r2 = diff(mounted: r1.newMountTree, next: node, handles: handles, handlers: handlers)

        let anyStructural = r2.patches.contains {
            switch $0 {
            case .createElement, .removeChild, .appendChild: return true
            default: return false
            }
        }
        #expect(!anyStructural, "re-render must reconcile the carrier in place, not replace it")
    }
}
