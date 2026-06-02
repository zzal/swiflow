// Sources/SwiflowTesting/TestRenderer.swift
import Swiflow
import SwiflowQuery

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
    /// Kept alive so @State's weak `_owner` reference doesn't dangle.
    let rootComponent: AnyComponent

    /// Owns this renderer's in-flight `.task` runs (Phase 20), so `settle()`
    /// awaits only this root's tasks — isolated from other (e.g. concurrently
    /// running) test renderers that share the process-global runtime.
    let taskScope = TaskScope()

    /// This render root's query client, installed as the render observer
    /// around each diff so `query()` during `body` reaches it.
    let queryClient: QueryClient

    init<C: Component>(_ instance: C, queryClient: QueryClient = QueryClient()) {
        let relay = RerenderRelay()
        self.handles = HandleAllocator()
        self.handlers = HandlerRegistry()
        self.queryClient = queryClient
        self.rootInstance = instance
        self.rootID = ObjectIdentifier(instance)
        self.scheduler = SyncScheduler { [relay] component in
            MainActor.assumeIsolated { relay.owner?.rerender(component) }
        }
        let anyComponent = AnyComponent(instance)
        self.rootComponent = anyComponent
        wireState(on: anyComponent, scheduler: self.scheduler)
        _testAmbientHandlers = self.handlers
        // Set the scope directly (not via the `withScope` closure) so we don't
        // capture `self` in a closure before all members are initialized.
        SwiflowTaskRuntime.currentScope = taskScope
        RenderObserverBox.current = queryClient
        defer {
            _testAmbientHandlers = nil
            SwiflowTaskRuntime.currentScope = nil
            RenderObserverBox.current = nil
        }
        // Wrap the root component's body evaluation in a query observer frame
        // so `query()` calls inside body are recorded and reconciled.
        queryClient.willEvaluate(owner: anyComponent, scheduler: self.scheduler)
        let rootBodyVNode = instance.body
        queryClient.didEvaluate()
        let result = diff(
            mounted: nil,
            next: rootBodyVNode,
            handles: self.handles,
            handlers: self.handlers,
            scheduler: self.scheduler
        )
        self.mountTree = result.newMountTree
        relay.owner = self
    }

    func rerender(_ component: AnyComponent) {
        _testAmbientHandlers = self.handlers
        SwiflowTaskRuntime.currentScope = taskScope
        RenderObserverBox.current = queryClient
        defer {
            _testAmbientHandlers = nil
            SwiflowTaskRuntime.currentScope = nil
            RenderObserverBox.current = nil
        }
        if ObjectIdentifier(component.instance) == rootID {
            // Wrap root body evaluation in a query observer frame.
            queryClient.willEvaluate(owner: rootComponent, scheduler: scheduler)
            let rootBodyVNode = rootInstance.body
            queryClient.didEvaluate()
            let result = diff(
                mounted: mountTree,
                next: rootBodyVNode,
                handles: handles,
                handlers: handlers,
                scheduler: scheduler
            )
            mountTree = result.newMountTree
        } else if let node = findComponentNode(component, in: mountTree) {
            // A nested component re-rendering on its own (its @State changed).
            // Its body is evaluated eagerly here, outside the diff's
            // `.component` path, so bracket it explicitly — exactly as the root
            // branch does — so `query()` calls reconcile. (The browser Renderer
            // re-renders the whole tree from root, where the diff fires the hook
            // for nested components; this keeps the TestRenderer faithful to it.)
            queryClient.willEvaluate(owner: component, scheduler: scheduler)
            let nestedBodyVNode = component.instance.body
            queryClient.didEvaluate()
            let result = diff(
                mounted: node.componentBody,
                next: nestedBodyVNode,
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
        case .fragment:
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
                if let filter = text {
                    if t.contains(filter) { results.append((node, data)) }
                } else {
                    results.append((node, data))
                }
            }
            for child in node.children {
                results += findElements(tag: tag, text: text, in: child)
            }
        case .fragment:
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
        if let c = node.component,
           ObjectIdentifier(c.instance) == ObjectIdentifier(component.instance) {
            return node
        }
        for child in node.children {
            if let found = findComponentNode(component, in: child) { return found }
        }
        if let body = node.componentBody {
            return findComponentNode(component, in: body)
        }
        return nil
    }

    func click(tag: String, text: String?) {
        let matches = findElements(tag: tag, text: text, in: mountTree)
        guard let (node, _) = matches.first,
              let id = node.handlerIds["click"] else { return }
        handlers.dispatch(id: id, event: EventInfo(type: "click"))
        scheduler.flush()
    }

    func input(tag: String, at index: Int, value: String) {
        let matches = findElements(tag: tag, text: nil, in: mountTree)
        guard index < matches.count else { return }
        let (node, _) = matches[index]
        guard let id = node.handlerIds["input"] else { return }
        handlers.dispatch(id: id, event: EventInfo(type: "input", targetValue: value))
        scheduler.flush()
    }

    func blur(tag: String, at index: Int) {
        let matches = findElements(tag: tag, text: nil, in: mountTree)
        guard index < matches.count else { return }
        let (node, _) = matches[index]
        guard let id = node.handlerIds["blur"] else { return }
        handlers.dispatch(id: id, event: EventInfo(type: "blur"))
        scheduler.flush()
    }

    func change(tag: String, at index: Int, value: String) {
        let matches = findElements(tag: tag, text: nil, in: mountTree)
        guard index < matches.count else { return }
        let (node, _) = matches[index]
        guard let id = node.handlerIds["change"] else { return }
        handlers.dispatch(id: id, event: EventInfo(type: "change", targetValue: value))
        scheduler.flush()
    }
}
