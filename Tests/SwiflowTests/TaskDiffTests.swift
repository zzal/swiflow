import Testing
@testable import Swiflow

@MainActor
@Suite("Task diff/reconcile")
struct TaskDiffTests {

    // Each test owns a TaskScope; `inScope` installs it around the synchronous
    // diff/start calls (re-installing before each one, since `currentScope` is a
    // process-global ambient that a concurrently-running test may have moved
    // during an `await`). This isolates these tests from siblings — in this
    // suite and others — without any global reset or .serialized.
    let scope = TaskScope()

    @discardableResult
    private func inScope<T>(_ body: () -> T) -> T {
        SwiflowTaskRuntime.withScope(scope) { body() }
    }

    private func drain() async {
        for t in scope.inFlightTasks() { await t.value }
    }

    @Test("startTasks spawns one slot and one run per declared binding") func startTasksSpawnsOnePerBinding() async {
        let node = MountNode(handle: 1, vnode: .element(ElementData(tag: "div")))
        var ran = 0
        inScope {
            startTasks(on: node, [
                TaskBinding(dependency: nil, body: { ran += 1 }),
                TaskBinding(dependency: AnyEquatableBox(1), body: { ran += 1 }),
            ])
        }
        #expect(node.taskSlots.count == 2)
        await drain()
        #expect(ran == 2)
    }

    @Test("Reconcile reruns a task only when its rerunOn dependency value changes") func reconcileRerunsOnlyWhenDependencyChanges() async {
        let node = MountNode(handle: 1, vnode: .element(ElementData(tag: "div")))
        var runs = 0
        inScope { startTasks(on: node, [TaskBinding(dependency: AnyEquatableBox(1), body: { runs += 1 })]) }
        await drain()
        #expect(runs == 1)

        // Same dependency -> no rerun.
        inScope { reconcileTasks(on: node, new: [TaskBinding(dependency: AnyEquatableBox(1), body: { runs += 1 })]) }
        await drain()
        #expect(runs == 1)

        // Changed dependency -> rerun.
        inScope { reconcileTasks(on: node, new: [TaskBinding(dependency: AnyEquatableBox(2), body: { runs += 1 })]) }
        await drain()
        #expect(runs == 2)
    }

    @Test("Switching between nil and a value dependency reruns the task in both directions") func gainingOrLosingDependencyReruns() async {
        let node = MountNode(handle: 1, vnode: .element(ElementData(tag: "div")))
        var runs = 0
        inScope { startTasks(on: node, [TaskBinding(dependency: nil, body: { runs += 1 })]) }
        await drain()
        #expect(runs == 1)

        // nil -> value: reruns (the (nil, value) switch arm).
        inScope { reconcileTasks(on: node, new: [TaskBinding(dependency: AnyEquatableBox(1), body: { runs += 1 })]) }
        await drain()
        #expect(runs == 2)

        // value -> nil: reruns (the (value, nil) switch arm).
        inScope { reconcileTasks(on: node, new: [TaskBinding(dependency: nil, body: { runs += 1 })]) }
        await drain()
        #expect(runs == 3)
    }

    @Test("A dependency-free task runs once at mount and never on reconcile") func bareTaskNeverReruns() async {
        let node = MountNode(handle: 1, vnode: .element(ElementData(tag: "div")))
        var runs = 0
        inScope { startTasks(on: node, [TaskBinding(dependency: nil, body: { runs += 1 })]) }
        await drain()
        inScope { reconcileTasks(on: node, new: [TaskBinding(dependency: nil, body: { runs += 1 })]) }
        await drain()
        #expect(runs == 1)   // bare task ran once, never again
    }

    @Test("cancelTasks clears the node's slots and cancels in-flight work") func cancelTasksTearsDownSlots() async {
        let node = MountNode(handle: 1, vnode: .element(ElementData(tag: "div")))
        inScope { startTasks(on: node, [TaskBinding(dependency: nil, body: { try? await Task.sleep(nanoseconds: 1_000_000_000) })]) }
        #expect(node.taskSlots.count == 1)
        cancelTasks(on: node)
        #expect(node.taskSlots.isEmpty)
        await drain()   // cancelled task completes
        #expect(scope.inFlightTasks().isEmpty)
    }

    @Test("Declaring a different `.task` count across renders fires a diagnostic but still grows the slots") func changingTaskCountFiresDiagnostic() async {
        let node = MountNode(handle: 1, vnode: .element(ElementData(tag: "div")))
        inScope { startTasks(on: node, [TaskBinding(dependency: AnyEquatableBox(1), body: {})]) }
        await drain()

        var captured: [String] = []
        let prior = _swiflowDiagnosticOverride
        _swiflowDiagnosticOverride = { captured.append($0) }
        defer { _swiflowDiagnosticOverride = prior }

        // New render declares two tasks where there was one — stable-slot violation.
        inScope {
            reconcileTasks(on: node,
                           new: [TaskBinding(dependency: AnyEquatableBox(1), body: {}),
                                 TaskBinding(dependency: nil, body: {})])
        }
        await drain()
        #expect(captured.contains { $0.contains("`.task` count") })
        // The grow path still ran past the diagnostic and started the extra slot.
        #expect(node.taskSlots.count == 2)
    }

    @Test("Mounting a vnode through diff starts its declared `.task` bodies") func mountStartsTasksDeclaredInBody() async {
        var ran = false
        let node = VNode.element(ElementData(tag: "div")).task { ran = true }
        let result = inScope { diff(mounted: nil, next: node, handles: HandleAllocator(), handlers: HandlerRegistry()) }
        #expect(result.newMountTree.taskSlots.count == 1)
        await drain()
        #expect(ran == true)
    }

    @Test("Destroying a subtree during diff cancels its in-flight tasks") func destroyCancelsTasks() async {
        var node = VNode.element(ElementData(tag: "div")).task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        let mounted = inScope { diff(mounted: nil, next: node, handles: HandleAllocator(), handlers: HandlerRegistry()) }.newMountTree
        #expect(scope.inFlightTasks().count == 1)

        // Replace the whole tree with a different tag -> old subtree destroyed.
        node = .element(ElementData(tag: "section"))
        inScope { _ = diff(mounted: mounted, next: node, handles: HandleAllocator(), handlers: HandlerRegistry()) }
        await drain()
        #expect(scope.inFlightTasks().isEmpty)
    }
}
