// Tests/SwiflowTests/Reactivity/ComponentMountTests.swift
import Testing
@testable import Swiflow

@Suite("Component mount path")
struct ComponentMountTests {

    final class Hello: Component {
        var body: VNode { h1("Hello") }
    }

    @Test("Mounting a bare component produces createElement patches for its body")
    func mountBareComponent() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let v = VNode.component(.init(Hello.self) { Hello() })

        let result = diff(mounted: nil, next: v, handles: handles, handlers: handlers)

        // We expect at minimum a createElement("h1") patch from the body.
        let createsH1 = result.patches.contains {
            if case .createElement(_, let tag) = $0, tag == "h1" { return true }
            return false
        }
        #expect(createsH1)

        // The returned mount tree's root is the component anchor; its
        // componentBody is the h1 mount node.
        let root = result.newMountTree
        if case .component = root.vnode {
            // ok
        } else {
            Issue.record("Root mount node should wrap .component, got \(root.vnode)")
        }
        #expect(root.component != nil, "Anchor should hold the AnyComponent instance")
        #expect(root.componentBody != nil, "Anchor should hold its mounted body")
        if case .element(let data) = root.componentBody?.vnode {
            #expect(data.tag == "h1")
        } else {
            Issue.record("componentBody should be an h1 element")
        }
    }

    @Test("Mounting a component as a child appends the body's DOM handle (not the anchor handle) to parent")
    func childComponentBodyHandleAppendedToParent() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let parent = div {
            component({ Hello() })
        }
        let result = diff(mounted: nil, next: parent, handles: handles, handlers: handlers)

        // Find the parent div's handle from its createElement patch.
        guard
            let createDiv = result.patches.first(where: { if case .createElement(_, let t) = $0, t == "div" { return true }; return false }),
            case .createElement(let parentHandle, _) = createDiv,
            let createH1 = result.patches.first(where: { if case .createElement(_, let t) = $0, t == "h1" { return true }; return false }),
            case .createElement(let h1Handle, _) = createH1
        else {
            Issue.record("Expected createElement patches for div and h1"); return
        }

        let appendsH1ToDiv = result.patches.contains {
            if case .appendChild(let p, let c) = $0, p == parentHandle, c == h1Handle { return true }
            return false
        }
        #expect(appendsH1ToDiv, "Parent div should appendChild the body's h1 handle, not the anchor handle")
    }

    @Test("MountNode.domHandle returns the body's handle for component anchors, own handle otherwise")
    func domHandleResolution() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()

        // Bare element: domHandle == handle.
        let elem = VNode.element(ElementData(tag: "p"))
        let elemResult = diff(mounted: nil, next: elem, handles: handles, handlers: handlers)
        #expect(elemResult.newMountTree.domHandle == elemResult.newMountTree.handle)

        // Component anchor: domHandle == componentBody.handle.
        let comp = VNode.component(.init(Hello.self) { Hello() })
        let compResult = diff(mounted: nil, next: comp, handles: handles, handlers: handlers)
        let anchor = compResult.newMountTree
        #expect(anchor.domHandle != anchor.handle)
        #expect(anchor.domHandle == anchor.componentBody?.handle)
    }
}
