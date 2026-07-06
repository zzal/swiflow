// Tests/SwiflowTests/DiffTests/SingleRootDOMHandleTests.swift
//
// `MountNode.singleRootDOMHandle` is the guarded root-attach handle: it descends
// through fragments and traps (in ALL builds) if the node resolves to anything
// other than exactly one DOM root. It replaced the root path's use of
// `domHandle`, which for a fragment root returned a bogus structural handle that
// silently reached mount/replaceMount in release (the DEBUG bare-fragment
// diagnostic being compiled out there).

import Testing
@testable import Swiflow

@Suite("singleRootDOMHandle — guarded root-attach handle")
@MainActor
struct SingleRootDOMHandleTests {

    final class DivRoot: Component {
        var body: VNode { .element(ElementData(tag: "div")) }
    }

    @Test("a single-element root resolves to that element's DOM handle (agrees with domHandle)")
    func singleElementRoot() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let tree = diff(
            mounted: nil,
            next: .component(.init(DivRoot.self) { DivRoot() }),
            handles: handles, handlers: handlers
        ).newMountTree

        #expect(collectDOMRoots(tree).count == 1)
        #expect(tree.singleRootDOMHandle == tree.domHandle,
                "for a single-rooted node the guarded accessor agrees with domHandle")
    }

    @Test("a fragment root (multiple DOM roots) traps in all builds")
    func fragmentRootTraps() async {
        await #expect(processExitsWith: .failure) {
            await MainActor.run {
                // A real diff of a fragment-root component would trap earlier at
                // the DEBUG bare-fragment diagnostic; build the node directly to
                // exercise THIS guard, which fires in every build (precondition).
                let frag = MountNode(handle: 0, vnode: .fragment([]))
                frag.addChild(MountNode(handle: 1, vnode: .element(ElementData(tag: "div"))))
                frag.addChild(MountNode(handle: 2, vnode: .element(ElementData(tag: "span"))))
                _ = frag.singleRootDOMHandle   // 2 roots → precondition failure
            }
        }
    }

    @Test("an empty root (zero DOM roots) also traps")
    func emptyFragmentRootTraps() async {
        await #expect(processExitsWith: .failure) {
            await MainActor.run {
                let frag = MountNode(handle: 0, vnode: .fragment([]))
                _ = frag.singleRootDOMHandle   // 0 roots → precondition failure
            }
        }
    }
}
