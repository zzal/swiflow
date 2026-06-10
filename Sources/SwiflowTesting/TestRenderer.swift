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
    /// Kept alive so @State's weak `_owner` reference doesn't dangle.
    let rootComponent: AnyComponent
    /// Root description with a same-instance factory — mirrors
    /// SwiflowDOM.Renderer.renderOnce(): the factory is consumed exactly once at
    /// first mount; every later diff at the same position reuses the instance.
    private let rootDescription: ComponentDescription

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
        let anyComponent = AnyComponent(instance)
        self.rootComponent = anyComponent
        self.rootDescription = ComponentDescription(
            typeID: anyComponent.typeID,
            key: nil,
            factory: { anyComponent }
        )
        self.scheduler = SyncScheduler { [relay] component in
            MainActor.assumeIsolated { relay.owner?.rerender(component) }
        }

        HandlerAmbient.current = self.handlers
        // Set the scope directly (not via the `withScope` closure) so we don't
        // capture `self` in a closure before all members are initialized.
        SwiflowTaskRuntime.currentScope = taskScope
        RenderObserverBox.current = queryClient
        defer {
            HandlerAmbient.current = nil
            SwiflowTaskRuntime.currentScope = nil
            RenderObserverBox.current = nil
        }
        // The diff's component-mount path does the rest — wireStateAndRestore,
        // handler scope, environment + observer bracketing, body evaluation —
        // the same code the browser renderer runs.
        let result = diff(
            mounted: nil,
            next: .component(rootDescription),
            handles: self.handles,
            handlers: self.handlers,
            scheduler: self.scheduler
        )
        self.mountTree = result.newMountTree
        firePostRenderLifecycle(result.newMountTree, preExistingIDs: [])
        relay.owner = self
    }

    /// Always re-renders from the root — exactly like the browser Renderer,
    /// where the RAF flush calls renderOnce() regardless of which component
    /// marked itself dirty. The diff decides which bodies to re-evaluate.
    func rerender(_ component: AnyComponent) {
        _ = component
        HandlerAmbient.current = self.handlers
        SwiflowTaskRuntime.currentScope = taskScope
        RenderObserverBox.current = queryClient
        defer {
            HandlerAmbient.current = nil
            SwiflowTaskRuntime.currentScope = nil
            RenderObserverBox.current = nil
        }
        let preExistingIDs = collectComponentIDs(mountTree)
        let result = diff(
            mounted: mountTree,
            next: .component(rootDescription),
            handles: handles,
            handlers: handlers,
            scheduler: scheduler
        )
        mountTree = result.newMountTree
        firePostRenderLifecycle(result.newMountTree, preExistingIDs: preExistingIDs)
    }

    /// Tears down the mounted tree: fires `onDisappear` (parent-first), closes
    /// handler scopes, and notifies the query client of component unmounts —
    /// mirroring SwiflowDOM.Renderer.teardown() minus the JS patches.
    func unmount() {
        RenderObserverBox.current = queryClient
        defer { RenderObserverBox.current = nil }
        var patches: [Patch] = []
        destroy(mountTree, into: &patches, handlers: handlers)
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
