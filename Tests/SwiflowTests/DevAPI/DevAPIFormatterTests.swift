// Tests/SwiflowTests/DevAPI/DevAPIFormatterTests.swift
import Testing
@testable import Swiflow

// MARK: - Shared test components

@MainActor @Component
private final class Leaf {
    var body: VNode { .text("x") }
}

@MainActor @Component
private final class Outer {
    var body: VNode { .text("") }
}

@MainActor @Component
private final class Counted {
    @State var count: Int = 0
    var body: VNode { .text("") }
}

// MARK: - Tree string tests

@Suite("DevAPIFormatter: treeString")
@MainActor
struct DevAPIFormatterTreeTests {

    @Test("single component with text body → short type name and empty path")
    func singleComponent() {
        let anchor = MountNode(
            handle: 0,
            vnode: .component(.init(Leaf.self) { Leaf() }),
            component: AnyComponent(Leaf()),
            componentBody: MountNode(handle: 1, vnode: .text("x"))
        )
        let out = DevAPIFormatter.treeString(from: anchor)
        #expect(out == #"Leaf """#)
    }

    @Test("component whose direct body is another component gets [body→] marker")
    func nestedComponentBody() {
        let innerAnchor = MountNode(
            handle: 2,
            vnode: .component(.init(Leaf.self) { Leaf() }),
            component: AnyComponent(Leaf()),
            componentBody: MountNode(handle: 3, vnode: .text(""))
        )
        let outerAnchor = MountNode(
            handle: 0,
            vnode: .component(.init(Outer.self) { Outer() }),
            component: AnyComponent(Outer()),
            componentBody: innerAnchor
        )
        let lines = DevAPIFormatter.treeString(from: outerAnchor).split(separator: "\n").map(String.init)
        #expect(lines.count == 2)
        #expect(lines[0] == #"Outer "" [body→]"#)
        #expect(lines[1] == #"  Leaf """#)
    }

    @Test("component whose body is an element (not a component) gets no [body→] marker")
    func elementBodyNoMarker() {
        let anchor = MountNode(
            handle: 0,
            vnode: .component(.init(Leaf.self) { Leaf() }),
            component: AnyComponent(Leaf()),
            componentBody: MountNode(handle: 1, vnode: .text(""))
        )
        let out = DevAPIFormatter.treeString(from: anchor)
        #expect(!out.contains("[body→]"))
    }

    @Test("element node with two component children → indexed paths, same indent level")
    func elementWithTwoComponentChildren() {
        let child0 = MountNode(
            handle: 2,
            vnode: .component(.init(Leaf.self) { Leaf() }),
            component: AnyComponent(Leaf()),
            componentBody: MountNode(handle: 3, vnode: .text(""))
        )
        let child1 = MountNode(
            handle: 4,
            vnode: .component(.init(Outer.self) { Outer() }),
            component: AnyComponent(Outer()),
            componentBody: MountNode(handle: 5, vnode: .text(""))
        )
        // Non-component wrapper (simulates an element node)
        let element = MountNode(handle: 1, vnode: .text(""), children: [child0, child1])
        let lines = DevAPIFormatter.treeString(from: element).split(separator: "\n").map(String.init)
        #expect(lines.count == 2)
        #expect(lines[0] == #"Leaf "0""#)
        #expect(lines[1] == #"Outer "1""#)
    }

    @Test("deeper nesting produces correct indentation and paths")
    func deepNesting() {
        // Outer (path "") → element body → Leaf (path "0")
        let leafAnchor = MountNode(
            handle: 4,
            vnode: .component(.init(Leaf.self) { Leaf() }),
            component: AnyComponent(Leaf()),
            componentBody: MountNode(handle: 5, vnode: .text(""))
        )
        let elementBody = MountNode(handle: 3, vnode: .text(""), children: [leafAnchor])
        let outerAnchor = MountNode(
            handle: 0,
            vnode: .component(.init(Outer.self) { Outer() }),
            component: AnyComponent(Outer()),
            componentBody: elementBody
        )
        let lines = DevAPIFormatter.treeString(from: outerAnchor).split(separator: "\n").map(String.init)
        #expect(lines.count == 2)
        #expect(lines[0] == #"Outer """#)
        #expect(lines[1] == #"  Leaf "0""#)
    }
}

// MARK: - State values tests

@Suite("DevAPIFormatter: stateValues")
@MainActor
struct DevAPIFormatterStateTests {

    @Test("stateValues returns nil when path has no matching component")
    func unknownPathReturnsNil() {
        let anchor = MountNode(
            handle: 0,
            vnode: .component(.init(Leaf.self) { Leaf() }),
            component: AnyComponent(Leaf()),
            componentBody: MountNode(handle: 1, vnode: .text(""))
        )
        #expect(DevAPIFormatter.stateValues(from: anchor, path: "99") == nil)
    }

    @Test("stateValues returns current @State values for the matching path")
    func matchingPathReturnsValues() {
        let c = Counted()
        c.count = 42
        let anchor = MountNode(
            handle: 0,
            vnode: .component(.init(Counted.self) { Counted() }),
            component: AnyComponent(c),
            componentBody: MountNode(handle: 1, vnode: .text(""))
        )
        let vals = DevAPIFormatter.stateValues(from: anchor, path: "")
        #expect((vals?["count"] as? Int) == 42)
    }

    @Test("stateValues finds a component at a nested path")
    func nestedPath() {
        let c = Counted()
        c.count = 7
        let nestedAnchor = MountNode(
            handle: 2,
            vnode: .component(.init(Counted.self) { Counted() }),
            component: AnyComponent(c),
            componentBody: MountNode(handle: 3, vnode: .text(""))
        )
        let element = MountNode(handle: 1, vnode: .text(""), children: [nestedAnchor])
        let outerAnchor = MountNode(
            handle: 0,
            vnode: .component(.init(Leaf.self) { Leaf() }),
            component: AnyComponent(Leaf()),
            componentBody: element
        )
        let vals = DevAPIFormatter.stateValues(from: outerAnchor, path: "0")
        #expect((vals?["count"] as? Int) == 7)
    }
}

// MARK: - Phase 19 format pinning (diff-based, full mount tree)

// Pins the exact output format of DevAPIFormatter.treeString. The Phase 19
// devtools panel parses this string to render the component tree, so any
// silent change to the format would break the panel without any test
// catching it on the Swift side. If you NEED to change the format, update
// this test deliberately and bump the panel's parser in lock-step.

@Suite("DevAPIFormatter.treeString output format is pinned for the Phase 19 panel parser")
@MainActor
struct DevAPIFormatterTreeStringTests {

    final class LeafComp: Component {
        var body: VNode { .text("leaf") }
    }

    final class MidComp: Component {
        var body: VNode { embed { LeafComp() } }
    }

    final class RootComp: Component {
        var body: VNode { embed { MidComp() } }
    }

    @Test("3-deep nested tree produces the canonical indented format with [body→] markers")
    func threeDeepCanonicalFormat() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let v = VNode.component(.init(RootComp.self) { RootComp() })
        let result = diff(mounted: nil, next: v, handles: handles, handlers: handlers)

        let out = DevAPIFormatter.treeString(from: result.newMountTree)

        // Format invariants the panel parser depends on:
        //   - one line per component anchor
        //   - "  " (two spaces) of indent per depth level
        //   - shortName + space + "\"<path>\""
        //   - " [body→]" suffix when the component's body is another component anchor
        //   - lines separated by "\n"
        let expected = """
            RootComp "" [body→]
              MidComp "" [body→]
                LeafComp ""
            """
        #expect(out == expected)
    }

    @Test("element with two child components renders both at the parent's depth with indexed paths")
    func elementWithComponentChildren() {
        final class ItemComp: Component {
            var body: VNode { .text("item") }
        }
        final class ContainerComp: Component {
            var body: VNode {
                .element(ElementData(tag: "div", children: [
                    .component(.init(ItemComp.self) { ItemComp() }),
                    .component(.init(ItemComp.self) { ItemComp() }),
                ]))
            }
        }

        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let v = VNode.component(.init(ContainerComp.self) { ContainerComp() })
        let result = diff(mounted: nil, next: v, handles: handles, handlers: handlers)

        let out = DevAPIFormatter.treeString(from: result.newMountTree)

        // ContainerComp's body is a div element (not a component anchor), so
        // no [body→] marker appears on the Container line. The two Item
        // component children of the div are walked at depth 1 with indexed paths.
        let expected = """
            ContainerComp ""
              ItemComp "0"
              ItemComp "1"
            """
        #expect(out == expected)
    }

    @Test("lines are joined with newline, not CRLF; no trailing newline")
    func lineEndingsAreUnixAndNoTrailingNewline() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let v = VNode.component(.init(RootComp.self) { RootComp() })
        let result = diff(mounted: nil, next: v, handles: handles, handlers: handlers)

        let out = DevAPIFormatter.treeString(from: result.newMountTree)

        #expect(!out.contains("\r"), "format must be LF, never CRLF")
        #expect(!out.hasSuffix("\n"), "no trailing newline")
        #expect(out.contains("\n"), "multi-line output uses '\\n' as separator")
    }
}
