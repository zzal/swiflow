// Tests/SwiflowTests/DevAPI/DevAPIFormatterTests.swift
import Testing
@testable import Swiflow

// MARK: - Shared test components

private final class Leaf: Component {
    var body: VNode { .text("x") }
}

private final class Outer: Component {
    var body: VNode { .text("") }
}

private final class Counted: Component {
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
