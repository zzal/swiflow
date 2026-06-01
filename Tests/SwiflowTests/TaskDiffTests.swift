import Testing
@testable import Swiflow

@MainActor
@Suite(.serialized)
struct TaskDiffTests {

    init() { SwiflowTaskRuntime._resetForTesting() }

    private func drain() async {
        for t in SwiflowTaskRuntime.inFlightTasks() { await t.value }
    }

    @Test func startTasksSpawnsOnePerBinding() async {
        let node = MountNode(handle: 1, vnode: .element(ElementData(tag: "div")))
        var ran = 0
        startTasks(on: node, [
            TaskBinding(dependency: nil, body: { ran += 1 }),
            TaskBinding(dependency: AnyEquatableBox(1), body: { ran += 1 }),
        ])
        #expect(node.taskSlots.count == 2)
        await drain()
        #expect(ran == 2)
    }

    @Test func reconcileRerunsOnlyWhenDependencyChanges() async {
        let node = MountNode(handle: 1, vnode: .element(ElementData(tag: "div")))
        var runs = 0
        startTasks(on: node, [TaskBinding(dependency: AnyEquatableBox(1), body: { runs += 1 })])
        await drain()
        #expect(runs == 1)

        // Same dependency -> no rerun.
        reconcileTasks(on: node, old: [TaskBinding(dependency: AnyEquatableBox(1), body: {})],
                       new: [TaskBinding(dependency: AnyEquatableBox(1), body: { runs += 1 })])
        await drain()
        #expect(runs == 1)

        // Changed dependency -> rerun.
        reconcileTasks(on: node, old: [TaskBinding(dependency: AnyEquatableBox(1), body: {})],
                       new: [TaskBinding(dependency: AnyEquatableBox(2), body: { runs += 1 })])
        await drain()
        #expect(runs == 2)
    }

    @Test func bareTaskNeverReruns() async {
        let node = MountNode(handle: 1, vnode: .element(ElementData(tag: "div")))
        var runs = 0
        startTasks(on: node, [TaskBinding(dependency: nil, body: { runs += 1 })])
        await drain()
        reconcileTasks(on: node, old: [TaskBinding(dependency: nil, body: {})],
                       new: [TaskBinding(dependency: nil, body: { runs += 1 })])
        await drain()
        #expect(runs == 1)   // bare task ran once, never again
    }

    @Test func cancelTasksTearsDownSlots() async {
        let node = MountNode(handle: 1, vnode: .element(ElementData(tag: "div")))
        startTasks(on: node, [TaskBinding(dependency: nil, body: { try? await Task.sleep(nanoseconds: 1_000_000_000) })])
        #expect(node.taskSlots.count == 1)
        cancelTasks(on: node)
        #expect(node.taskSlots.isEmpty)
        await drain()   // cancelled task completes
        #expect(SwiflowTaskRuntime.inFlightTasks().isEmpty)
    }

    @Test func changingTaskCountFiresDiagnostic() async {
        let node = MountNode(handle: 1, vnode: .element(ElementData(tag: "div")))
        startTasks(on: node, [TaskBinding(dependency: AnyEquatableBox(1), body: {})])
        await drain()

        var captured: [String] = []
        let prior = _swiflowDiagnosticOverride
        _swiflowDiagnosticOverride = { captured.append($0) }
        defer { _swiflowDiagnosticOverride = prior }

        // New render declares two tasks where there was one — stable-slot violation.
        reconcileTasks(on: node,
                       old: [TaskBinding(dependency: AnyEquatableBox(1), body: {})],
                       new: [TaskBinding(dependency: AnyEquatableBox(1), body: {}),
                             TaskBinding(dependency: nil, body: {})])
        await drain()
        #expect(captured.contains { $0.contains("`.task` count") })
    }
}
