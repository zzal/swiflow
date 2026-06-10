// Tests/SwiflowTests/Reactivity/RefTests.swift
//
// Task E — Phase 7. Validates `Ref<Element>`, `AnyRefBinding`, the
// `Attribute.refBinding(_:)` case, and the mount/destroy/update wiring
// in Diff. SwiflowDOM's `.ref(_:)` modifier is covered transitively by
// `Attribute.refBinding(AnyRefBinding(ref))` here — the `.ref(_:)`
// factory in SwiflowDOM is just `.refBinding(AnyRefBinding(ref))`.
// Resolver wiring (`RefResolverInstall.resolver`) is browser-only and
// covered by the Playwright e2e smoke test in Task G.
import Testing
@testable import Swiflow

@Suite("Ref<Element> lifecycle")
@MainActor
struct RefTests {

    // MARK: - Storage round-trips

    @Test("Ref initializes with nil handle")
    func initialHandleIsNil() {
        let ref = Ref<Int>()
        #expect(ref.handle == nil)
    }

    @Test("Ref.projectedValue returns self")
    func projectedValueIsSelf() {
        let ref = Ref<Int>()
        #expect(ref.projectedValue === ref)
    }

    @Test("AnyRefBinding.setHandle writes through to the wrapped Ref")
    func setHandleWrites() {
        let ref = Ref<Int>()
        let binding = AnyRefBinding(ref)
        binding.setHandle(42)
        #expect(ref.handle == 42)
    }

    @Test("AnyRefBinding.clearHandle nils the wrapped Ref's handle")
    func clearHandleNils() {
        let ref = Ref<Int>()
        let binding = AnyRefBinding(ref)
        binding.setHandle(7)
        binding.clearHandle()
        #expect(ref.handle == nil)
    }

    // MARK: - DSL fold

    @Test(".refBinding case is collected into ElementData.refBindings")
    func refBindingCollected() {
        let ref = Ref<Int>()
        let node = div(.refBinding(AnyRefBinding(ref)))
        guard case .element(let data) = node else {
            Issue.record("expected element"); return
        }
        #expect(data.refBindings.count == 1)
    }

    @Test("Multiple refBindings on one element are all preserved")
    func multipleRefBindings() {
        let a = Ref<Int>()
        let b = Ref<Int>()
        let node = div(
            .refBinding(AnyRefBinding(a)),
            .refBinding(AnyRefBinding(b))
        )
        guard case .element(let data) = node else {
            Issue.record("expected element"); return
        }
        #expect(data.refBindings.count == 2)
    }

    @Test(".refBinding nested in a .compound flattens correctly")
    func refBindingInsideCompound() {
        let ref = Ref<Int>()
        let node = div(.compound([
            .attr("data-foo", "bar"),
            .refBinding(AnyRefBinding(ref)),
        ]))
        guard case .element(let data) = node else {
            Issue.record("expected element"); return
        }
        #expect(data.attributes["data-foo"] == "bar")
        #expect(data.refBindings.count == 1)
    }

    @Test("ElementData equality ignores refBindings")
    func equalityIgnoresRefBindings() {
        // Two structurally identical elements compare equal even when one
        // carries a Ref binding and the other doesn't. Refs are out-of-band
        // metadata for the Diff; they're not part of the rendered shape.
        let ref = Ref<Int>()
        let withRef = ElementData(tag: "div", refBindings: [AnyRefBinding(ref)])
        let without = ElementData(tag: "div")
        #expect(withRef == without)
    }

    // MARK: - Mount

    @Test("Diff.mount populates ref.handle with the allocated element handle")
    func mountPopulatesHandle() {
        let ref = Ref<Int>()
        let handles = HandleAllocator(start: 100)
        let handlers = HandlerRegistry()
        let node = div(.refBinding(AnyRefBinding(ref)))

        let result = diff(mounted: nil, next: node, handles: handles, handlers: handlers)
        // First allocation off the allocator → handle == 100.
        #expect(ref.handle == 100)
        #expect(result.newMountTree.handle == 100)
    }

    @Test("Diff.mount binds refs on nested elements too")
    func mountBindsNestedRefs() {
        let inner = Ref<Int>()
        let handles = HandleAllocator(start: 0)
        let handlers = HandlerRegistry()
        let node = VNode.element(ElementData(
            tag: "div",
            children: [
                .element(ElementData(
                    tag: "span",
                    refBindings: [AnyRefBinding(inner)]
                ))
            ]
        ))

        _ = diff(mounted: nil, next: node, handles: handles, handlers: handlers)
        // Parent <div> gets handle 0; child <span> gets handle 1.
        #expect(inner.handle == 1)
    }

    // MARK: - Destroy

    @Test("Diff.destroy clears ref.handle when the element is unmounted")
    func destroyClearsHandle() {
        let ref = Ref<Int>()
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let withRef = div(.refBinding(AnyRefBinding(ref)))
        let replacement = VNode.text("gone")

        let mount = diff(mounted: nil, next: withRef, handles: handles, handlers: handlers)
        #expect(ref.handle != nil)

        // Replace .element with .text → triggers the default arm in update()
        // which destroys the old subtree and mounts fresh.
        _ = diff(mounted: mount.newMountTree, next: replacement, handles: handles, handlers: handlers)
        #expect(ref.handle == nil, "destroy should clear the ref's handle")
    }

    // MARK: - Update (in-place re-render of the same element)

    @Test("Same-tag re-render with the same ref keeps ref.handle bound to the same handle")
    func updateKeepsRefBound() {
        let ref = Ref<Int>()
        let handles = HandleAllocator(start: 0)
        let handlers = HandlerRegistry()
        let before = div(.refBinding(AnyRefBinding(ref)), .attr("data-x", "1"))
        let after = div(.refBinding(AnyRefBinding(ref)), .attr("data-x", "2"))

        let mount = diff(mounted: nil, next: before, handles: handles, handlers: handlers)
        let initialHandle = ref.handle
        #expect(initialHandle != nil)

        _ = diff(mounted: mount.newMountTree, next: after, handles: handles, handlers: handlers)
        // The element survived the update — DOM node didn't move, handle
        // didn't change, ref should still point at the same handle.
        #expect(ref.handle == initialHandle)
    }

    @Test("Same-tag re-render that drops the ref clears the dropped ref's handle")
    func updateClearsDroppedRef() {
        let ref = Ref<Int>()
        let handles = HandleAllocator(start: 0)
        let handlers = HandlerRegistry()
        let before = div(.refBinding(AnyRefBinding(ref)))
        let after = div(.attr("data-x", "1"))  // ref dropped on re-render

        let mount = diff(mounted: nil, next: before, handles: handles, handlers: handlers)
        #expect(ref.handle != nil)

        _ = diff(mounted: mount.newMountTree, next: after, handles: handles, handlers: handlers)
        #expect(ref.handle == nil, "ref no longer present in newData should be cleared")
    }
}
