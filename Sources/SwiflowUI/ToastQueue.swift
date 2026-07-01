// Sources/SwiflowUI/ToastQueue.swift
import Swiflow

/// A managed Toast queue as a `Reducer` (use with `@ReducerState var toasts: ToastQueue`).
/// Shows at most `maxVisible` toasts; extras wait in a FIFO `pending` queue and are
/// promoted as visible ones dismiss. Duplicate toasts (same message + variant) coalesce
/// into a single entry with a recurrence `count` instead of stacking. Pure & synchronous —
/// the per-toast auto-dismiss timer lives in `ToastView` (a pending toast isn't rendered,
/// so its timer never starts until promoted).
public struct ToastQueue: Reducer {
    public struct State {
        public var visible: [ToastItem] = []   // rendered, ≤ maxVisible
        public var pending: [ToastItem] = []   // FIFO overflow, not rendered
        public init() {}
    }
    public enum Action {
        case show(ToastItem)
        case dismiss(String)   // by id
        case dismissAll
    }

    let maxVisible: Int
    public init(maxVisible: Int = 3) { self.maxVisible = maxVisible }
    public var initialState: State { .init() }

    public func reduce(into s: inout State, _ action: Action) {
        switch action {
        case .show(let item):
            // Coalesce first — a duplicate never consumes a slot.
            if let i = s.visible.firstIndex(where: { $0.dedupKey == item.dedupKey }) {
                s.visible[i].count += 1
            } else if let j = s.pending.firstIndex(where: { $0.dedupKey == item.dedupKey }) {
                s.pending[j].count += 1
            } else if s.visible.count < maxVisible {
                s.visible.append(item)
            } else {
                s.pending.append(item)
            }
        case .dismiss(let id):
            s.visible.removeAll { $0.id == id }
            s.pending.removeAll { $0.id == id }
            refill(&s)
        case .dismissAll:
            s.visible.removeAll()
            s.pending.removeAll()
        }
    }

    /// Promote pending → visible (FIFO) until full or drained.
    private func refill(_ s: inout State) {
        while s.visible.count < maxVisible, !s.pending.isEmpty {
            s.visible.append(s.pending.removeFirst())
        }
    }
}

/// Renders a `ToastQueue`'s visible toasts. Mount once (e.g. app root):
///
///     @ReducerState var toasts: ToastQueue
///     …
///     Button("Save") { self.$toasts.send(.show(ToastItem("Saved!", variant: .success))) }
///     ToastStack(queue: $toasts)
///
/// Only `state.visible` renders; each toast auto-dismisses (or via ✕) and dispatches
/// `.dismiss(id)`, which promotes the next pending toast. Duplicates show a live `×N` badge.
@MainActor
public func ToastStack(queue: ReducerHandle<ToastQueue>,
                       placement: ToastPlacement = .bottomTrailing) -> VNode {
    ensureBaseStyles()
    installControlSheet(id: "sw-toast", toastStyleSheet)
    let children = queue.state.visible.map { item in
        // Keyed by id so the instance + its dismiss timer survive re-renders. The count
        // is fed LIVE (not from the frozen `item`) so a coalesce bump updates the badge
        // in place — re-keying would remount and flicker.
        embed(item.id) {
            ToastView(
                item: item,
                recurrences: { queue.state.visible.first { $0.id == item.id }?.count ?? 1 },
                onDismiss: { queue.send(.dismiss(item.id)) }
            )
        }
    }
    return element("div",
                   attributes: [.class("sw-toast-stack sw-toast-stack--\(placement.modifierClass)")],
                   children: children)
}
