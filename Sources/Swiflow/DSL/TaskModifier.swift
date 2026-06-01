// Sources/Swiflow/DSL/TaskModifier.swift
//
// Postfix `.task` / `.task(rerunOn:)` modifiers. They attach a TaskBinding to
// the decorated element's out-of-band `taskBindings`; the diff starts/reruns/
// cancels them along the node lifecycle. See SwiflowTaskRuntime + Diff/DiffTasks.

public extension VNode {
    /// Run an async effect once when this node mounts; cancel it when the node
    /// unmounts. Never restarts. Declared in `body` but run later by the
    /// runtime on the main actor — `body` itself stays pure.
    func task(_ body: @escaping TaskBody) -> VNode {
        appendTask(TaskBinding(dependency: nil, body: body))
    }

    /// Run an async effect when this node mounts; cancel and re-run it whenever
    /// `rerunOn` changes (`!=`) between renders; cancel it when the node
    /// unmounts. `rerunOn` is an explicit re-run trigger — not an exhaustive
    /// dependency audit. Compose several dependencies into one `Equatable`
    /// struct or array.
    func task<Dependency: Equatable>(rerunOn dependency: Dependency, _ body: @escaping TaskBody) -> VNode {
        appendTask(TaskBinding(dependency: AnyEquatableBox(dependency), body: body))
    }

    private func appendTask(_ binding: TaskBinding) -> VNode {
        if case .element(var data) = self {
            data.taskBindings.append(binding)
            return .element(data)
        }
        swiflowDiagnostic("`.task` applied to a non-element VNode. Tasks attach to an element — e.g. `div { … }.task { … }`. The modifier is ignored.")
        return self
    }
}
