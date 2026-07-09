// Sources/SwiflowTesting/TestRenderer.swift
import Swiflow
import SwiflowQuery

private final class RerenderRelay: @unchecked Sendable {
    weak var owner: TestRenderer?
}

@MainActor
final class TestRenderer {
    private(set) var mountTree: MountNode
    private var isUnmounted = false
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

        // Plain calls, not a closure-based bracket: self.mountTree isn't
        // assigned yet, and Swift forbids capturing self in a closure before
        // every stored property is set (see RenderContext.swift's doc).
        installRenderContext(handlers: self.handlers, taskScope: taskScope, observer: queryClient)
        defer { uninstallRenderContext() }
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
        installRenderContext(handlers: self.handlers, taskScope: taskScope, observer: queryClient)
        defer { uninstallRenderContext() }
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
    // destroy() cancels .task effects via each node's stored TaskSlot handle —
    // no task-scope ambient needed here.
    func unmount() {
        guard !isUnmounted else { return }
        isUnmounted = true
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

    /// Mirrors the JS driver's serializeEvent(): snapshot the target's current
    /// `value`/`checked` from the mount tree the way the browser snapshots them
    /// from the live DOM (js-driver/swiflow-driver.js:70-80). Returns nils for
    /// elements without those properties — same as the driver's `"value" in
    /// target` / `"checked" in target` guards.
    private func targetSnapshot(of node: MountNode) -> (value: String?, checked: Bool?) {
        guard case .element(let data) = node.vnode else { return (nil, nil) }
        var value: String? = nil
        var checked: Bool? = nil
        if let v = data.properties["value"] {
            switch v {
            case .string(let s): value = s
            case .int(let i): value = String(i)
            case .double(let d): value = String(d)
            case .bool(let b): value = String(b)
            }
        }
        if case .bool(let b)? = data.properties["checked"] { checked = b }
        return (value, checked)
    }

    /// Why an interaction could not dispatch (audit VI Wave-1: the five
    /// interactions used to `guard … else { return }` — a typo'd selector
    /// silently no-opped and the assertion three lines later failed with a
    /// bare "expected non-nil"). Carried up to the harness, which records a
    /// test Issue naming the reason and the candidates.
    enum InteractionFailure: CustomStringConvertible {
        case noMatch(tag: String, text: String?, tagsPresent: [String])
        case indexOutOfRange(tag: String, index: Int, matchCount: Int)
        case noHandler(event: String, tag: String, handlersPresent: [String])

        var description: String {
            switch self {
            case .noMatch(let tag, let text, let present):
                let textPart = text.map { " with text \"\($0)\"" } ?? ""
                let candidates = present.isEmpty ? "none" : present.joined(separator: ", ")
                return "no <\(tag)>\(textPart) in the rendered tree — tags present: \(candidates)"
            case .indexOutOfRange(let tag, let index, let count):
                return "index \(index) is out of range — only \(count) <\(tag)> element(s) rendered"
            case .noHandler(let event, let tag, let present):
                let handlers = present.isEmpty ? "none" : present.joined(separator: ", ")
                return "the matched <\(tag)> has no \"\(event)\" handler — handlers present: \(handlers)"
            }
        }
    }

    /// One dispatch core for every interaction. Returns nil on success, or
    /// the reason nothing was dispatched.
    func dispatch(event: String, tag: String, text: String?, index: Int,
                  payload: ((value: String?, checked: Bool?)) -> EventInfo) -> InteractionFailure? {
        let matches = findElements(tag: tag, text: text, in: mountTree)
        guard !matches.isEmpty else {
            return .noMatch(tag: tag, text: text, tagsPresent: allTagsPresent())
        }
        guard index < matches.count else {
            return .indexOutOfRange(tag: tag, index: index, matchCount: matches.count)
        }
        let (node, data) = matches[index]
        guard let id = node.handlerIds[event] else {
            return .noHandler(event: event, tag: data.tag,
                              handlersPresent: node.handlerIds.keys.sorted())
        }
        handlers.dispatch(id: id, event: payload(targetSnapshot(of: node)))
        scheduler.flush()
        return nil
    }

    /// Distinct tags in document order — the candidate list for no-match failures.
    private func allTagsPresent() -> [String] {
        var seen: Set<String> = []
        var out: [String] = []
        func walk(_ node: MountNode) {
            if case .element(let data) = node.vnode, seen.insert(data.tag).inserted {
                out.append(data.tag)
            }
            if let body = node.componentBody { walk(body) }
            for child in node.children { walk(child) }
        }
        walk(mountTree)
        return out
    }

    @discardableResult
    func click(tag: String, text: String?) -> InteractionFailure? {
        dispatch(event: "click", tag: tag, text: text, index: 0) {
            EventInfo(type: "click", targetValue: $0.value, targetChecked: $0.checked)
        }
    }

    @discardableResult
    func input(tag: String, at index: Int, value: String) -> InteractionFailure? {
        dispatch(event: "input", tag: tag, text: nil, index: index) {
            EventInfo(type: "input", targetValue: value, targetChecked: $0.checked)
        }
    }

    @discardableResult
    func blur(tag: String, at index: Int) -> InteractionFailure? {
        dispatch(event: "blur", tag: tag, text: nil, index: index) {
            EventInfo(type: "blur", targetValue: $0.value, targetChecked: $0.checked)
        }
    }

    @discardableResult
    func change(tag: String, at index: Int, value: String) -> InteractionFailure? {
        dispatch(event: "change", tag: tag, text: nil, index: index) {
            EventInfo(type: "change", targetValue: value, targetChecked: $0.checked)
        }
    }

    /// Simulates toggling a checkbox/radio: dispatches `change` with
    /// `targetChecked` — the payload shape `.checked(_:)` bindings read.
    @discardableResult
    func check(tag: String, at index: Int, checked: Bool) -> InteractionFailure? {
        dispatch(event: "change", tag: tag, text: nil, index: index) {
            EventInfo(type: "change", targetValue: $0.value, targetChecked: checked)
        }
    }
}
