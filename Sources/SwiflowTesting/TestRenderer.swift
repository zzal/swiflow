// Sources/SwiflowTesting/TestRenderer.swift
import Swiflow

private final class RerenderRelay: @unchecked Sendable {
    weak var owner: TestRenderer?
}

@MainActor
final class TestRenderer {
    private(set) var mountTree: MountNode
    let handles: HandleAllocator
    let handlers: HandlerRegistry
    let scheduler: SyncScheduler
    let rootInstance: any Component
    let rootID: ObjectIdentifier

    init<C: Component>(_ instance: C) {
        let relay = RerenderRelay()
        self.handles = HandleAllocator()
        self.handlers = HandlerRegistry()
        self.rootInstance = instance
        self.rootID = ObjectIdentifier(instance)
        self.scheduler = SyncScheduler { [relay] component in
            MainActor.assumeIsolated { relay.owner?.rerender(component) }
        }
        let anyComponent = AnyComponent(instance)
        wireState(on: anyComponent, scheduler: self.scheduler)
        _testAmbientHandlers = self.handlers
        defer { _testAmbientHandlers = nil }
        let result = diff(
            mounted: nil,
            next: instance.body,
            handles: self.handles,
            handlers: self.handlers,
            scheduler: self.scheduler
        )
        self.mountTree = result.newMountTree
        relay.owner = self
    }

    func rerender(_ component: AnyComponent) {
        _testAmbientHandlers = self.handlers
        defer { _testAmbientHandlers = nil }
        if ObjectIdentifier(component.instance) == rootID {
            let result = diff(
                mounted: mountTree,
                next: rootInstance.body,
                handles: handles,
                handlers: handlers,
                scheduler: scheduler
            )
            mountTree = result.newMountTree
        } else if let node = findComponentNode(component, in: mountTree) {
            let result = diff(
                mounted: node.componentBody,
                next: component.instance.body,
                handles: handles,
                handlers: handlers,
                scheduler: scheduler
            )
            node.componentBody = result.newMountTree
        }
    }

    func textContent(of node: MountNode) -> String {
        switch node.vnode {
        case .text(let s):
            return s
        case .element:
            return node.children.map { textContent(of: $0) }.joined()
        case .component:
            return node.componentBody.map { textContent(of: $0) } ?? ""
        case .environmentOverride:
            return node.componentBody.map { textContent(of: $0) } ?? ""
        default:
            return ""
        }
    }

    var allText: String { textContent(of: mountTree) }

    func findElements(
        tag: String,
        text: String?,
        in node: MountNode
    ) -> [(MountNode, ElementData)] {
        var results: [(MountNode, ElementData)] = []
        switch node.vnode {
        case .element(let data):
            if data.tag == tag {
                let t = textContent(of: node)
                if text == nil || t.contains(text!) {
                    results.append((node, data))
                }
            }
            for child in node.children {
                results += findElements(tag: tag, text: text, in: child)
            }
        case .component, .environmentOverride:
            if let body = node.componentBody {
                results += findElements(tag: tag, text: text, in: body)
            }
        default:
            break
        }
        return results
    }

    func findComponentNode(
        _ component: AnyComponent,
        in node: MountNode
    ) -> MountNode? {
        fatalError("implemented in Task 4")
    }
}
