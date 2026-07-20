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

    /// Live DOM-state side-tables, keyed by MountNode
    /// handle. The browser's `element.value`/`checked` change on user input
    /// whether or not any render declares them (uncontrolled inputs), so the
    /// declared-properties bag alone under-reports what an event snapshot
    /// would carry. Exactly the real DOM's two writers feed these: user
    /// input (recorded at input/change dispatch) and committed renders
    /// (value/checked `setProperty` patches, applied in `applyDOMStatePatches`).
    private var domValues: [Int: String] = [:]
    private var domChecked: [Int: Bool] = [:]

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
        // Batch mode: ONE render per flush regardless of
        // how many components marked dirty — RAFScheduler's per-frame
        // contract. The per-component mode double-diffed and double-fired
        // onChange whenever one interaction dirtied two components.
        self.scheduler = SyncScheduler.batching { [relay] dirtyIDs in
            MainActor.assumeIsolated { relay.owner?.flushDirty(dirtyIDs) }
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
        applyDOMStatePatches(result.patches)
        firePostRenderLifecycle(result.newMountTree, preExistingIDs: [])
        relay.owner = self
    }

    /// Applies the value/checked slice of a committed patch batch to the
    /// DOM-state side-tables — the harness's micro-DOM for exactly the two
    /// properties event snapshots read. A render assigning `element.value`
    /// overwrites whatever the user "typed", like the real driver.
    private func applyDOMStatePatches(_ patches: [Patch]) {
        for patch in patches {
            switch patch {
            case .setProperty(let handle, "value", let value):
                domValues[handle] = flattenProperty(value)
            case .setProperty(let handle, "checked", let value):
                if case .bool(let b) = value { domChecked[handle] = b }
            case .removeProperty(let handle, "value"):
                domValues.removeValue(forKey: handle)
            case .removeProperty(let handle, "checked"):
                domChecked.removeValue(forKey: handle)
            case .destroyNode(let handle):
                domValues.removeValue(forKey: handle)
                domChecked.removeValue(forKey: handle)
            default:
                break
            }
        }
    }

    /// One flush batch → one render, running the SAME `planRerender` →
    /// `scopedRerender`/full flow as `Renderer.flushDirty(_:)`: the common single-dirty case takes the browser's scoped path
    /// — the parent body is NOT re-evaluated, exactly like production since
    /// PR #90. The plan decision and both diff paths are the shared package
    /// core; only patch shipping (browser) vs discarding (here) differs.
    func flushDirty(_ dirtyIDs: Set<ObjectIdentifier>) {
        switch planRerender(root: mountTree, dirtyIDs: dirtyIDs) {
        case .full:
            renderFullRoot()
        case .scoped(let anchor):
            installRenderContext(handlers: handlers, taskScope: taskScope, observer: queryClient)
            defer { uninstallRenderContext() }
            let scoped = scopedRerender(
                anchor: anchor,
                handles: handles,
                handlers: handlers,
                scheduler: scheduler
            )
            applyDOMStatePatches(scoped.patches)
            // The scoped diff mutated the anchor's subtree in place — the
            // mount tree stays valid, no reassignment (same as the browser).
            firePostRenderLifecycle(scoped.newMountTree, preExistingIDs: scoped.preExistingIDs)
        }
    }

    /// The full-root render — `Renderer.renderOnce()` minus patch shipping.
    private func renderFullRoot() {
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
        applyDOMStatePatches(result.patches)
        mountTree = result.newMountTree
        firePostRenderLifecycle(result.newMountTree, preExistingIDs: preExistingIDs)
    }

    /// Tears down the mounted tree: fires `onDisappear` (parent-first), closes
    /// handler scopes, and notifies the query client of component unmounts —
    /// the SAME `teardownMountTree` routine SwiflowDOM.Renderer.teardown()
    /// runs, minus shipping the removal patches.
    // destroy() cancels .task effects via each node's stored TaskSlot handle —
    // no task-scope ambient needed here.
    func unmount() {
        guard !isUnmounted else { return }
        isUnmounted = true
        _ = teardownMountTree(mountTree, handlers: handlers, observer: queryClient)
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

    /// Tag(+text) query, expressed over the one generic walk in
    /// Queries.swift — same traversal as every role/label/class query.
    func findElements(
        tag: String,
        text: String?,
        in node: MountNode
    ) -> [(MountNode, ElementData)] {
        findElements(in: node) { n, data in
            guard data.tag == tag else { return false }
            guard let filter = text else { return true }
            return textContent(of: n).contains(filter)
        }
    }

    /// Mirrors the JS driver's serializeEvent(): snapshot the target's current
    /// `value`/`checked` the way the browser snapshots them from the live DOM
    /// (js-driver/swiflow-driver.js:70-80). Reads the DOM-state side-tables
    /// first — they carry user input on uncontrolled elements that no render
    /// ever declares — falling back to the declared
    /// properties bag. Returns nils for elements with neither, same as the
    /// driver's `"value" in target` / `"checked" in target` guards.
    private func targetSnapshot(of node: MountNode) -> (value: String?, checked: Bool?) {
        guard case .element(let data) = node.vnode else { return (nil, nil) }
        var value: String? = domValues[node.handle]
        var checked: Bool? = domChecked[node.handle]
        if value == nil, let v = data.properties["value"] {
            value = flattenProperty(v)
        }
        if checked == nil, case .bool(let b)? = data.properties["checked"] { checked = b }
        return (value, checked)
    }

    /// Why an interaction could not dispatch. Carried up to the harness, which records a
    /// test Issue naming the reason and the candidates.
    enum InteractionFailure: CustomStringConvertible {
        case noMatch(tag: String, text: String?, tagsPresent: [String])
        case indexOutOfRange(tag: String, index: Int, matchCount: Int)
        case noHandler(event: String, tag: String, handlersPresent: [String])
        case detached(tag: String, event: String)

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
            case .detached(let tag, let event):
                return "cannot \"\(event)\" this <\(tag)>: the node was removed from the tree "
                    + "by a re-render since it was found — re-query for the current element"
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
        return dispatch(event: event, on: matches[index].0, payload: payload)
    }

    /// Node-targeted dispatch — the live-TestNode action path. Fires on THE given element, never re-queried, and refuses
    /// nodes a re-render has detached (their handler IDs may point at closed
    /// scopes — firing would be a ghost interaction no browser can perform).
    func dispatch(event: String, on node: MountNode,
                  payload: ((value: String?, checked: Bool?)) -> EventInfo) -> InteractionFailure? {
        guard case .element(let data) = node.vnode else {
            return .noHandler(event: event, tag: "?", handlersPresent: [])
        }
        guard isAttached(node) else {
            return .detached(tag: data.tag, event: event)
        }
        let info = payload(targetSnapshot(of: node))
        // The DOM writes BEFORE any listener runs: typing/toggling changes
        // element.value/checked whether or not anyone handles the event
        // (uncontrolled inputs).
        if info.type == "input" || info.type == "change" {
            if let v = info.targetValue { domValues[node.handle] = v }
            if let c = info.targetChecked { domChecked[node.handle] = c }
        }
        guard let id = node.handlerIds[event] else {
            // input/change without a listener is NOT a no-op — the DOM state
            // above changed, which is all the browser would do too. Every
            // other event with no handler stays a strict failure.
            if event == "input" || event == "change" { return nil }
            return .noHandler(event: event, tag: data.tag,
                              handlersPresent: node.handlerIds.keys.sorted())
        }
        handlers.dispatch(id: id, event: info)
        scheduler.flush()
        return nil
    }

    /// Human-readable dump of the rendered tree — the
    /// payload for `TestHarness.expect` failures and `TestHarness.debug()`.
    /// One line per node: elements as `<tag attrs on:[events]>`, text nodes
    /// quoted, component anchors as `▸ TypeName`. Fragments are invisible in
    /// the DOM, so they add no line and no indent.
    func dump() -> String {
        var lines: [String] = []
        func walk(_ node: MountNode, depth: Int) {
            let pad = String(repeating: "  ", count: depth)
            switch node.vnode {
            case .text(let s):
                lines.append("\(pad)\"\(s)\"")
            case .element(let data):
                var bits = [data.tag]
                bits += data.attributes.sorted { $0.key < $1.key }
                    .map { "\($0.key)=\"\($0.value)\"" }
                bits += data.properties.sorted { $0.key < $1.key }
                    .map { "prop:\($0.key)=\"\(flattenProperty($0.value))\"" }
                let events = node.handlerIds.keys.sorted()
                if !events.isEmpty { bits.append("on:[\(events.joined(separator: ","))]") }
                lines.append("\(pad)<\(bits.joined(separator: " "))>")
                for child in node.children { walk(child, depth: depth + 1) }
            case .fragment:
                for child in node.children { walk(child, depth: depth) }
            case .component, .environmentOverride:
                var bodyDepth = depth
                if let any = node.component {
                    lines.append("\(pad)▸ \(String(describing: type(of: any.instance)))")
                    bodyDepth += 1
                }
                if let body = node.componentBody { walk(body, depth: bodyDepth) }
            default:
                break
            }
        }
        walk(mountTree, depth: 0)
        return lines.joined(separator: "\n")
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
