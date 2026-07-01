// Tests/SwiflowUITests/ToastQueueTests.swift
import Testing
@testable import Swiflow
@testable import SwiflowUI

@MainActor private func el(_ node: VNode?) -> ElementData? {
    if case .element(let d)? = node { return d }; return nil
}

@Suite("ToastQueue reducer")
@MainActor
struct ToastQueueReducerTests {
    private func reduced(_ q: ToastQueue, _ start: ToastQueue.State,
                         _ actions: [ToastQueue.Action]) -> ToastQueue.State {
        var s = start
        for a in actions { q.reduce(into: &s, a) }
        return s
    }

    @Test("show under cap goes visible; over cap goes pending")
    func capAndOverflow() {
        let q = ToastQueue(maxVisible: 2)
        let s = reduced(q, q.initialState, [
            .show(ToastItem("a")), .show(ToastItem("b")), .show(ToastItem("c")),
        ])
        #expect(s.visible.map(\.message) == ["a", "b"])
        #expect(s.pending.map(\.message) == ["c"])
    }

    @Test("dismissing a visible toast FIFO-promotes the pending head")
    func promoteOnDismiss() {
        let q = ToastQueue(maxVisible: 2)
        let a = ToastItem("a"); let b = ToastItem("b"); let c = ToastItem("c")
        var s = reduced(q, q.initialState, [.show(a), .show(b), .show(c)])
        s = reduced(q, s, [.dismiss(a.id)])
        #expect(s.visible.map(\.message) == ["b", "c"])
        #expect(s.pending.isEmpty)
    }

    @Test("dismiss with empty pending just shrinks; unknown id is a no-op")
    func dismissEdges() {
        let q = ToastQueue(maxVisible: 3)
        let a = ToastItem("a"); let b = ToastItem("b")
        var s = reduced(q, q.initialState, [.show(a), .show(b)])
        s = reduced(q, s, [.dismiss("nope")])
        #expect(s.visible.count == 2)
        s = reduced(q, s, [.dismiss(a.id)])
        #expect(s.visible.map(\.message) == ["b"])
    }

    @Test("dismissAll clears both queues")
    func clearAll() {
        let q = ToastQueue(maxVisible: 1)
        var s = reduced(q, q.initialState, [.show(ToastItem("a")), .show(ToastItem("b"))])
        s = reduced(q, s, [.dismissAll])
        #expect(s.visible.isEmpty && s.pending.isEmpty)
    }

    @Test("same message+variant coalesces into count without a new slot")
    func coalesceVisible() {
        let q = ToastQueue(maxVisible: 3)
        let s = reduced(q, q.initialState, [
            .show(ToastItem("Saved", variant: .success)),
            .show(ToastItem("Saved", variant: .success)),
            .show(ToastItem("Saved", variant: .success)),
        ])
        #expect(s.visible.count == 1)
        #expect(s.visible[0].count == 3)
    }

    @Test("coalesce bumps a pending duplicate; different variant is distinct")
    func coalescePendingAndVariant() {
        let q = ToastQueue(maxVisible: 1)
        var s = reduced(q, q.initialState, [
            .show(ToastItem("x", variant: .info)),
            .show(ToastItem("y", variant: .info)),
            .show(ToastItem("y", variant: .info)),
        ])
        #expect(s.visible.count == 1 && s.pending.count == 1)
        #expect(s.pending[0].count == 2)
        s = reduced(q, s, [.show(ToastItem("x", variant: .danger))])
        #expect(s.pending.count == 2)
    }
}

@Suite("ToastStack(queue:) rendering")
@MainActor
struct ToastStackQueueTests {
    private func handle(_ q: ToastQueue) -> ReducerHandle<ToastQueue> {
        ReducerHandle(runtime: ReducerRuntime<ToastQueue>(), reducer: q)
    }

    @Test("renders only visible toasts, and not pending")
    func rendersVisibleOnly() {
        let h = handle(ToastQueue(maxVisible: 2))
        h.send(.show(ToastItem("a"))); h.send(.show(ToastItem("b"))); h.send(.show(ToastItem("c")))
        let root = el(ToastStack(queue: h))!
        #expect(root.children.count == 2)   // c is pending, not rendered
    }
}
