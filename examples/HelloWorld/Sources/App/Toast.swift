// Sources/App/Toast.swift
import Swiflow
import SwiflowWeb
import JavaScriptKit

/// Toast — top-layer notification using the Popover API.
///
/// - `popover="manual"` keeps the toast on the top layer without
///   light-dismiss (other clicks aren't hijacked).
/// - Auto-dismisses after 2.5s via `after(_:do:)`; the timer is cancelled
///   in `onDisappear` so an early parent unmount doesn't fire `onDone`.
/// - `exitAnimation` / `exitDuration` still drive the exit animation when
///   the parent toggles `showToast = false`.
@MainActor @Component
final class Toast {
    let message: String
    let onDone: () -> Void
    let root = Ref<JSObject>()
    var dismissTimer: TimerHandle?

    init(message: String, onDone: @escaping () -> Void) {
        self.message = message
        self.onDone = onDone
    }

    static var exitAnimation: String? = "toast-out 0.2s ease forwards"
    static var exitDuration: Double?  = 0.2

    var body: VNode {
        div(.attr("popover", "manual"),
            .attr("role", "status"),
            .attr("aria-live", "polite"),
            .ref(root),
            .on(.click) { self.onDone() }) {
            span(.class("icon"), .attr("aria-hidden", "true")) { text("\u{2713}") }
            text(message)
        }
    }

    func onAppear() {
        if let el = root.wrappedValue {
            _ = el.showPopover?()
        }
        dismissTimer = after(2.5) { [weak self] in self?.onDone() }
    }

    func onDisappear() {
        dismissTimer?.cancel()
        dismissTimer = nil
    }
}
