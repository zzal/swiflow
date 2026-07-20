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

@MainActor private final class ToastHostStub: Component { var body: VNode { .text("") } }

@Suite("ToastStack(queue:) rendering")
@MainActor
struct ToastStackQueueTests {
    // Wire the runtime like production does (a mounted @Component owns it), so
    // dispatching through it is faithful and doesn't trip the unwired warning.
    // The owner is held at suite scope because the runtime's `owner` is `weak`
    // — a temporary wrapper would deallocate before send() and read as unwired.
    private let owner = AnyComponent(ToastHostStub())
    private let scheduler = SyncScheduler { _ in }
    private func handle(_ q: ToastQueue) -> ReducerHandle<ToastQueue> {
        let rt = ReducerRuntime<ToastQueue>()
        rt.wire(owner: owner, scheduler: scheduler)
        return ReducerHandle(runtime: rt, reducer: q)
    }

    @Test("renders only visible toasts, and not pending")
    func rendersVisibleOnly() {
        let h = handle(ToastQueue(maxVisible: 2))
        h.send(.show(ToastItem("a"))); h.send(.show(ToastItem("b"))); h.send(.show(ToastItem("c")))
        let root = el(ToastStack(queue: h))!
        #expect(root.children.count == 2)   // c is pending, not rendered
    }

    @Test("$toasts.show sugar — one call, no ToastItem/Action ceremony")
    func showVerbSugar() {
        let h = handle(ToastQueue())
        h.show("Saved", .success)
        h.show("Plain default")   // variant defaults to .info like ToastItem's init
        #expect(h.state.visible.count == 2)
        #expect(h.state.visible[0].message == "Saved")
        #expect(h.state.visible[0].variant == .success)
        #expect(h.state.visible[1].variant == .info)
    }

    @Test("show sugar coalesces exactly like the longhand — same dedup semantics")
    func showVerbCoalesces() {
        let h = handle(ToastQueue())
        h.show("Copied", .success)
        h.show("Copied", .success)
        #expect(h.state.visible.count == 1)
        #expect(h.state.visible[0].count == 2, "recurrence badge, not a second toast")
    }
}

// MARK: - Numeric-input guardrails (synchronous warn-capture only — the
// _swiflowWarnOverride seam must never be held across a suspension)

@Suite("Toast numeric guardrails")
@MainActor
struct ToastGuardrailTests {

    private func capturingWarns<T>(_ body: () -> T) -> (value: T, warns: [String]) {
        var warns: [String] = []
        let prior = _swiflowWarnOverride
        _swiflowWarnOverride = { warns.append($0) }
        defer { _swiflowWarnOverride = prior }
        return (body(), warns)
    }

    @Test("ToastQueue clamps maxVisible < 1 to 1, with a DEBUG warn")
    func maxVisibleClamped() {
        let (queue, warns) = capturingWarns { ToastQueue(maxVisible: 0) }
        #expect(queue.maxVisible == 1)
        #expect(warns.contains { $0.contains("maxVisible") })
        // Clamped queue still renders: one show goes visible, not pending.
        var s = queue.initialState
        queue.reduce(into: &s, .show(ToastItem("a")))
        #expect(s.visible.count == 1)
        #expect(s.pending.isEmpty)
    }

    @Test("valid maxVisible does not warn")
    func validMaxVisibleSilent() {
        let (queue, warns) = capturingWarns { ToastQueue(maxVisible: 3) }
        #expect(queue.maxVisible == 3)
        #expect(warns.isEmpty)
    }

    @Test("ToastItem warns on a non-positive duration (behavior unchanged: immediate dismiss)")
    func nonPositiveDurationWarns() {
        let (item, warns) = capturingWarns { ToastItem("x", duration: 0) }
        #expect(item.duration == 0)
        #expect(warns.contains { $0.contains("duration") })
        let (_, quiet) = capturingWarns { ToastItem("y") }
        #expect(quiet.isEmpty)
    }
}
