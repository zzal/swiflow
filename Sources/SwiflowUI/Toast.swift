// Sources/SwiflowUI/Toast.swift
import Swiflow
import SwiflowDOM   // after() / TimerHandle for auto-dismiss (WASM-runtime; see ToastView)

/// Severity of a `Toast`, mapped to an accent color + a live-region politeness.
/// Matches the rest of the palette (accent/success/danger/warning; see Theme.swift /
/// Badge). `.danger` is announced assertively.
public enum ToastVariant: Equatable {
    case info, success, danger, warning
    var modifierClass: String {
        switch self {
        case .info:    return "info"
        case .success: return "success"
        case .danger:  return "danger"
        case .warning: return "warning"
        }
    }
    /// Danger interrupts (role=alert + aria-live=assertive); info/success/warning are polite.
    var isAssertive: Bool { self == .danger }
}

/// Where the `ToastStack` anchors. Default `.bottomTrailing` (bottom-right).
public enum ToastPlacement: Equatable {
    case topLeading, topTrailing, topCenter, bottomLeading, bottomTrailing, bottomCenter
    var modifierClass: String {
        switch self {
        case .topLeading:     return "top-leading"
        case .topTrailing:    return "top-trailing"
        case .topCenter:      return "top-center"
        case .bottomLeading:  return "bottom-leading"
        case .bottomTrailing: return "bottom-trailing"
        case .bottomCenter:   return "bottom-center"
        }
    }
}

/// One queued toast. Carries a stable auto-generated `id` so the `ToastStack` can
/// key each toast's component instance (survives reorders; removal animates cleanly).
/// Construct with just a message: `toasts.append(ToastItem("Saved!", variant: .success))`.
@MainActor
public struct ToastItem {
    public let id: String
    public let message: String
    public let variant: ToastVariant
    public let duration: Double   // seconds before auto-dismiss

    public init(_ message: String, variant: ToastVariant = .info, duration: Double = 4) {
        self.id = nextSwID("sw-toast")
        self.message = message
        self.variant = variant
        self.duration = duration
    }
}

/// A positioned region that renders an app-owned queue of toasts. The app owns the
/// array; mount the stack once (e.g. at the app root) and fire by appending:
///
///     @State var toasts: [ToastItem] = []
///     …
///     Button("Save") { toasts.append(ToastItem("Saved!", variant: .success)) }
///     ToastStack(toasts: $toasts)
///
/// Each toast auto-dismisses after its `duration` (or via its ✕) and removes itself
/// from the bound array — no global presenter, just `@State` + the existing timer. The
/// region is `pointer-events: none` so empty space never blocks the page; toasts opt
/// back in. (Uses a high `z-index`, not the top layer, so a toast can sit under a modal
/// `<dialog>` — an accepted trade-off for not needing a popover host.)
@MainActor
public func ToastStack(toasts: Binding<[ToastItem]>, placement: ToastPlacement = .bottomTrailing) -> VNode {
    ensureBaseStyles()
    installControlSheet(id: "sw-toast", toastStyleSheet)

    let children = toasts.get().map { item in
        // Keyed by id: the instance (and its dismiss timer) survives re-renders;
        // dropping the item unmounts it → exitAnimation plays.
        //
        // NB: keyed `embed` runs the factory only on FIRST mount, so this `ToastView`'s
        // `item`/`onDismiss` freeze for the instance's life. That's correct here because
        // id↔content is 1:1 and immutable — a changed toast is a *new* item with a new id,
        // hence a new instance. `onDismiss` deliberately reads `toasts.get()` live (not a
        // captured snapshot), so it removes against the current array regardless of the freeze.
        embed(item.id) {
            ToastView(item: item, onDismiss: { removeToast(item.id, from: toasts) })
        }
    }
    return element("div",
                   attributes: [.class("sw-toast-stack sw-toast-stack--\(placement.modifierClass)")],
                   children: children)
}

/// Removes the toast with `id` from the bound queue. Pulled out of the `onDismiss`
/// closure so the queue logic is unit-testable on host (the timer that drives it isn't).
/// Idempotent: removing an absent id is a no-op; order of the survivors is preserved.
@MainActor
func removeToast(_ id: String, from toasts: Binding<[ToastItem]>) {
    toasts.set(toasts.get().filter { $0.id != id })
}

/// One rendered toast. A `@Component` because it owns the auto-dismiss timer
/// (`onAppear`/`onDisappear`) and the slide-out (`exitAnimation`, which fires here
/// precisely because the toast *unmounts* when removed — unlike the dialogs, which
/// stay mounted and only toggle `[open]`).
@MainActor @Component
final class ToastView {
    private let item: ToastItem
    private let onDismiss: () -> Void
    // Pause the auto-dismiss while the pointer is over OR focus is within the toast
    // (WCAG 2.2.1 — give users enough time; keyboard users need to reach the ✕).
    private var isHovered = false
    private var isFocused = false
    #if canImport(JavaScriptKit)
    private var dismissTimer: TimerHandle?
    #endif

    init(item: ToastItem, onDismiss: @escaping () -> Void) {
        self.item = item
        self.onDismiss = onDismiss
    }

    var body: VNode {
        ensureBaseStyles()
        installControlSheet(id: "sw-toast", toastStyleSheet)
        return element("div", attributes: [
            .class("sw-toast sw-toast--\(item.variant.modifierClass)"),
            .attr("role", item.variant.isAssertive ? "alert" : "status"),
            .attr("aria-live", item.variant.isAssertive ? "assertive" : "polite"),
            // Pause/resume the countdown on hover + keyboard focus (focusin/out bubble
            // from the ✕). Resume restarts the full duration only when neither holds.
            .on(.custom("mouseenter")) { self.isHovered = true;  self.reschedule() },
            .on(.custom("mouseleave")) { self.isHovered = false; self.reschedule() },
            .on(.custom("focusin"))    { self.isFocused = true;  self.reschedule() },
            .on(.custom("focusout"))   { self.isFocused = false; self.reschedule() },
        ], children: [
            element("span", attributes: [.class("sw-toast__message")], children: [text(item.message)]),
            element("button", attributes: [
                .class("sw-toast__close"),
                .attr("type", "button"),
                .attr("aria-label", "Dismiss"),
                .on(.click) { self.onDismiss() },
            ], children: [text("\u{00D7}")]),   // ×
        ])
    }

    func onAppear() { reschedule() }
    func onDisappear() { stopTimer() }   // unmounted (dismissed/parent gone) — don't fire late

    /// Cancel any pending auto-dismiss, then arm a fresh one — unless paused by
    /// hover/focus. Idempotent; safe to call from every pause/resume transition.
    private func reschedule() {
        stopTimer()
        #if canImport(JavaScriptKit)
        guard !isHovered, !isFocused else { return }
        dismissTimer = after(item.duration) { [weak self] in self?.onDismiss() }
        #endif
    }

    private func stopTimer() {
        #if canImport(JavaScriptKit)
        dismissTimer?.cancel()
        dismissTimer = nil
        #endif
    }

    // Slide/fade out on unmount. Duration is token-driven (reduced-motion → 0s → instant).
    static var exitAnimation: String? = "sw-toast-out var(--sw-duration) var(--sw-ease) forwards"
    static var exitDuration: Double? = 0.2
}

/// Global `.sw-toast*` sheet. Stack positioning per placement; each toast is a surface
/// card with a variant-colored leading edge (no soft tint, so text stays on `--sw-surface`
/// and never hits the light-mode tint-contrast trap). Entry/exit read `--sw-duration`, so
/// reduced-motion makes them instant.
let toastStyleSheet: CSSSheet = css {
    raw("""
    .sw-toast-stack {
      position: fixed;
      z-index: 1000;
      display: flex;
      flex-direction: column;
      gap: var(--sw-space-sm);
      padding: var(--sw-space-lg);
      max-width: min(90vw, 28rem);
      pointer-events: none;             /* gaps/empty region never block the page */
    }
    .sw-toast-stack--top-leading     { top: 0;    left: 0;  align-items: flex-start; }
    .sw-toast-stack--top-trailing    { top: 0;    right: 0; align-items: flex-end; }
    .sw-toast-stack--top-center      { top: 0;    left: 50%; transform: translateX(-50%); align-items: center; }
    .sw-toast-stack--bottom-leading  { bottom: 0; left: 0;  align-items: flex-start; }
    .sw-toast-stack--bottom-trailing { bottom: 0; right: 0; align-items: flex-end; }
    .sw-toast-stack--bottom-center   { bottom: 0; left: 50%; transform: translateX(-50%); align-items: center; }

    .sw-toast {
      pointer-events: auto;            /* but the toasts themselves are interactive */
      display: flex;
      align-items: center;
      gap: var(--sw-space-md);
      min-width: 16rem;
      max-width: 100%;
      padding: var(--sw-space-md) var(--sw-space-lg);
      background-color: var(--sw-surface);
      color: var(--sw-text);
      border-radius: var(--sw-radius);
      border-inline-start: 4px solid var(--sw-accent);   /* info accent (default) */
      box-shadow: var(--sw-shadow);
      animation: sw-toast-in var(--sw-duration) var(--sw-ease);
    }
    .sw-toast--info    { border-inline-start-color: var(--sw-info); }
    .sw-toast--success { border-inline-start-color: var(--sw-success); }
    .sw-toast--danger  { border-inline-start-color: var(--sw-danger); }
    .sw-toast--warning { border-inline-start-color: var(--sw-warning); }

    .sw-toast__message { flex: 1 1 auto; }

    .sw-toast__close {
      flex: 0 0 auto;
      appearance: none;
      border: none;
      background: transparent;
      color: var(--sw-text-muted);
      font: inherit;
      font-size: 1.25rem;
      line-height: 1;
      padding: 0 0.125rem;
      cursor: pointer;
      border-radius: var(--sw-radius-sm);
    }
    .sw-toast__close:hover { color: var(--sw-text); }
    .sw-toast__close:focus-visible {
      outline: var(--sw-focus-ring-width) solid var(--sw-focus-ring);
      outline-offset: 2px;
    }

    @keyframes sw-toast-in {
      from { opacity: 0; transform: translateY(8px); }
      to   { opacity: 1; transform: translateY(0); }
    }
    @keyframes sw-toast-out {
      from { opacity: 1; transform: translateY(0); }
      to   { opacity: 0; transform: translateY(8px); }
    }
    """)
}
