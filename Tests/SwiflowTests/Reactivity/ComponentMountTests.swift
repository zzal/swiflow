// Tests/SwiflowTests/Reactivity/ComponentMountTests.swift
import Testing
@testable import Swiflow

@Suite("Component mount path")
@MainActor
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

    @Test("Destroying a component anchor emits destroyNode for the body's DOM nodes")
    func destroyAnchorEmitsBodyDestroys() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()

        // Mount a component, then trigger destroy() via update()'s default
        // arm: re-render the same tree position as a plain element. The
        // diff falls through to destroy(old) + mount(new).
        let v1 = VNode.component(.init(Hello.self) { Hello() })
        let v2 = VNode.element(ElementData(tag: "p"))

        let first = diff(mounted: nil, next: v1, handles: handles, handlers: handlers)
        // Capture the body's domHandle BEFORE update — it's what should
        // appear in the destroyNode patch.
        let bodyDOMHandle = first.newMountTree.domHandle

        let second = diff(mounted: first.newMountTree, next: v2, handles: handles, handlers: handlers)

        let destroysBody = second.patches.contains {
            if case .destroyNode(let h) = $0, h == bodyDOMHandle { return true }
            return false
        }
        #expect(destroysBody, "destroy() must emit destroyNode for the body's DOM handle when an anchor is replaced")

        // The anchor's own handle should NEVER be in a destroyNode patch
        // (the driver never knew about it).
        let anchorHandle = first.newMountTree.handle
        let destroysAnchor = second.patches.contains {
            if case .destroyNode(let h) = $0, h == anchorHandle { return true }
            return false
        }
        #expect(!destroysAnchor, "Anchor's structural handle must not be destroyed — driver never saw it")
    }

    @Test("domHandle walks chains of nested component anchors (depth ≥ 2)")
    func domHandleNestedAnchors() {
        // A wrapper component whose body is another component — nested
        // anchors. domHandle should walk through both to reach the leaf
        // element. A single-level dereference (body?.handle instead of
        // body?.domHandle) would silently return the inner anchor's
        // structural handle here.
        final class Wrapper: Component {
            var body: VNode { component({ Hello() }) }
        }

        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let v = VNode.component(.init(Wrapper.self) { Wrapper() })
        let result = diff(mounted: nil, next: v, handles: handles, handlers: handlers)

        let outerAnchor = result.newMountTree
        let innerAnchor = outerAnchor.componentBody
        let leafBody = innerAnchor?.componentBody

        // Sanity: the structure should be outer anchor → inner anchor → h1
        #expect(innerAnchor != nil, "Outer anchor should have an inner anchor as its body")
        #expect(leafBody != nil, "Inner anchor should have the h1 mount as its body")

        // The load-bearing assertion: domHandle resolves all the way down.
        #expect(outerAnchor.domHandle == leafBody?.handle, "Outer.domHandle must equal the leaf's handle, NOT the inner anchor's structural handle")
        #expect(outerAnchor.domHandle != innerAnchor?.handle, "Outer.domHandle must NOT be the inner anchor's handle (that would be a single-level deref bug)")
    }

    @Test("Inserting a component child into a parent's children list uses the body's DOM handle")
    func insertComponentChildUsesDOMHandle() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()

        // First render: parent with one element child.
        let v1 = div { p("first") }
        let first = diff(mounted: nil, next: v1, handles: handles, handlers: handlers)

        // Second render: SAME parent, but now with a component child appended.
        // The indexed children-diff helper appends a new node — its appendChild
        // patch must reference the body's DOM handle, not the anchor's
        // structural handle.
        let v2 = div {
            p("first")
            component({ Hello() })
        }
        let second = diff(mounted: first.newMountTree, next: v2, handles: handles, handlers: handlers)

        // Find the h1 createElement and confirm its handle appears in an
        // appendChild patch on the div (parent).
        guard
            let createH1 = second.patches.first(where: { if case .createElement(_, let t) = $0, t == "h1" { return true }; return false }),
            case .createElement(let h1Handle, _) = createH1
        else {
            Issue.record("Expected createElement for h1 in second render's patches: \(second.patches)"); return
        }
        let divHandle = first.newMountTree.handle

        let appendsH1 = second.patches.contains {
            if case .appendChild(let p, let c) = $0, p == divHandle, c == h1Handle { return true }
            return false
        }
        #expect(appendsH1, "Append of component child must reference the body h1's handle (\(h1Handle)) on parent div (\(divHandle)), got patches: \(second.patches)")
    }
}
