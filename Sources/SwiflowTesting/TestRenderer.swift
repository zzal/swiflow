// Sources/SwiflowTesting/TestRenderer.swift
import Swiflow

private final class RerenderRelay: @unchecked Sendable {
    weak var owner: TestRenderer?
}

@MainActor
final class TestRenderer {
    var mountTree: MountNode
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
        let any = AnyComponent(instance)
        wireState(on: any, scheduler: self.scheduler)
        _testAmbientHandlers = self.handlers
        let result = diff(
            mounted: nil,
            next: instance.body,
            handles: self.handles,
            handlers: self.handlers,
            scheduler: self.scheduler
        )
        _testAmbientHandlers = nil
        self.mountTree = result.newMountTree
        relay.owner = self
    }

    func rerender(_ component: AnyComponent) {
        _testAmbientHandlers = self.handlers
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
        _testAmbientHandlers = nil
    }

    func textContent(of node: MountNode) -> String {
        switch node.vnode {
        case .text(let s):
            return s
        case .element:
            return node.children.map { textContent(of: $0) }.joined()
        case .component:
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
        fatalError("implemented in Task 3")
    }

    func findComponentNode(
        _ component: AnyComponent,
        in node: MountNode
    ) -> MountNode? {
        fatalError("implemented in Task 4")
    }
}
