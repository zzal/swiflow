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
        fatalError("implemented in Task 2")
    }
}
