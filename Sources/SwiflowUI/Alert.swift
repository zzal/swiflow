// Sources/SwiflowUI/Alert.swift
import Swiflow
#if canImport(JavaScriptKit)
import JavaScriptKit
#endif

/// A modal alert dialog. SwiftUI-style declarative API: bind `isPresented` and the
/// alert opens/closes to match. Built on a native `<dialog>` driven by
/// `showModal()`/`close()` (so it's a true modal — top layer, backdrop, focus trap,
/// ESC-to-close, all native), with token-driven styling and `@starting-style` entry
/// animation. Dismissal is ESC + the action buttons you provide (click-outside isn't
/// wired — `EventInfo` has no target identity yet, roadmap #4); the native `close`
/// event (incl. ESC) writes `isPresented` back to `false`.
///
/// Returns an embedded component, so it can sit directly in a parent's `body`:
///
///     @State var confirmDelete = false
///     …
///     Button("Delete…", variant: .secondary) { confirmDelete = true }
///     Alert("Delete this item?", isPresented: $confirmDelete, message: "This can't be undone.") {
///         Button("Cancel", variant: .secondary) { confirmDelete = false }
///         Button("Delete") { delete(); confirmDelete = false }
///     }
///
/// > Note: `title`/`message`/`actions` are captured when the alert is **first
/// > presented** (the underlying component is `embed`-reused across renders, so its
/// > stored props don't update live; the `isPresented` binding *does* stay live).
/// > That's the right model for an alert — its text is fixed per logical alert. If
/// > you genuinely need the content to change while mounted, key the embed yourself:
/// > `embed("\(title)") { … }`.
@MainActor
public func Alert(
    _ title: String,
    isPresented: Binding<Bool>,
    message: String? = nil,
    @ChildrenBuilder actions: @escaping () -> [VNode]
) -> VNode {
    embed { AlertDialog(title: title, isPresented: isPresented, message: message, actions: actions) }
}

/// The stateful implementation behind `Alert`. A `@Component` because a *modal*
/// dialog needs the imperative `showModal()` (the `open` attribute alone is
/// non-modal) — synced to `isPresented` in `onChange`/`onAppear`. The JS-interop
/// bits are `#if`-gated so the dialog structure still builds + unit-tests on host.
@MainActor @Component
final class AlertDialog {
    private let title: String
    private let message: String?
    private let isPresented: Binding<Bool>
    private let actions: () -> [VNode]
    // Stable ids for ARIA wiring, captured once at init (not per body) so they're
    // stable across re-renders and never collide between two instances.
    private let titleID: String
    private let messageID: String
    #if canImport(JavaScriptKit)
    private let dialogRef = Ref<JSObject>()
    #endif

    init(title: String, isPresented: Binding<Bool>, message: String? = nil, actions: @escaping () -> [VNode]) {
        self.title = title
        self.isPresented = isPresented
        self.message = message
        self.actions = actions
        self.titleID = nextSwID("sw-alert-title")
        self.messageID = nextSwID("sw-alert-msg")
    }

    var body: VNode {
        ensureBaseStyles()
        installControlSheet(id: "sw-alert", alertStyleSheet)

        var attrs: [Attribute] = [
            .class("sw-alert"),
            .attr("role", "alertdialog"),                 // an alert that requires a response
            .attr("aria-labelledby", titleID),            // name = the visible <h2> (stays in sync)
            // Native close (ESC, close(), or a form method=dialog) → sync the binding back.
            // Guarded: this handler exists for *user*-driven closes; when we drive the close
            // ourselves (binding went false → syncOpenState calls close()), the native `close`
            // event still fires, and writing an already-false binding would schedule a wasted render.
            .on(.custom("close")) { if self.isPresented.get() { self.isPresented.set(false) } },
        ]
        if message != nil { attrs.append(.attr("aria-describedby", messageID)) }  // description = the message
        #if canImport(JavaScriptKit)
        attrs.append(.refBinding(AnyRefBinding(dialogRef)))
        #endif

        var children: [VNode] = [
            element("h2", attributes: [.class("sw-alert__title"), .attr("id", titleID)], children: [text(title)]),
        ]
        if let message {
            children.append(element("p", attributes: [.class("sw-alert__message"), .attr("id", messageID)], children: [text(message)]))
        }
        children.append(element("div", attributes: [.class("sw-alert__actions")], children: actions()))
        return element("dialog", attributes: attrs, children: children)
    }

    func onAppear() { syncOpenState() }
    func onChange() { syncOpenState() }

    /// Drive the native modal state from `isPresented`.
    ///
    /// Read-diff-write, deliberately idempotent: `onChange` fires after *every* app
    /// render (the framework walks the whole committed tree post-render, not just
    /// changed components), so this runs constantly — the `el.open` diff guard is what
    /// makes that safe and cheap. Do NOT "optimize" the guard away. `onAppear` runs
    /// post-commit (ref handles are set at element mount, before this lifecycle pass),
    /// so the `<dialog>` is guaranteed resolved here — an `isPresented: true`-at-mount
    /// alert opens correctly. `showModal()`/`close()` set `.open` synchronously; the
    /// native `close` event is queued as a separate task, so there's no re-entrancy here.
    private func syncOpenState() {
        #if canImport(JavaScriptKit)
        guard let el = dialogRef.wrappedValue else { return }   // nil on host / pre-mount → no-op
        let want = isPresented.get()
        let isOpen = el.open.boolean ?? false
        if want, !isOpen {
            _ = el.showModal?()
        } else if !want, isOpen {
            _ = el.close?()
        }
        #endif
    }
}

/// Global `.sw-alert` sheet (the dialog state selectors — `[open]`, `::backdrop`,
/// `@starting-style` — are cleanest as unscoped raw CSS). Backdrop reads the M2
/// overlay tokens, so reduced-transparency solidifies it; transitions read
/// `--sw-duration`, so reduced-motion drops the animation.
///
/// `@starting-style` + `transition-behavior: allow-discrete` are Baseline 2024
/// (Chrome 117+, Safari 17.4+, Firefox 129+). On older engines the dialog still
/// *functions* — `showModal()` works — it just snaps open/closed without the
/// transition. Graceful degradation, intentional floor.
let alertStyleSheet: CSSSheet = css {
    raw("""
    .sw-alert {
      margin: auto;                       /* center in the viewport */
      min-width: 30ch;
      max-width: min(90vw, 28rem);
      border: none;
      border-radius: var(--sw-radius);
      background-color: var(--sw-surface);
      color: var(--sw-text);
      padding: var(--sw-space-lg);
      box-shadow: var(--sw-shadow);
      opacity: 0;
      transform: translateY(8px) scale(0.98);
      transition: opacity var(--sw-duration) var(--sw-ease),
                  transform var(--sw-duration) var(--sw-ease),
                  overlay var(--sw-duration) var(--sw-ease) allow-discrete,
                  display var(--sw-duration) var(--sw-ease) allow-discrete;
    }
    .sw-alert[open] {
      opacity: 1;
      transform: translateY(0) scale(1);
    }
    @starting-style {
      .sw-alert[open] { opacity: 0; transform: translateY(8px) scale(0.98); }
    }
    .sw-alert::backdrop {
      background-color: var(--sw-overlay-bg);
      -webkit-backdrop-filter: var(--sw-backdrop);
      backdrop-filter: var(--sw-backdrop);
    }
    .sw-alert__title {
      margin: 0 0 var(--sw-space-sm);
      font-size: 1.125rem;
      font-weight: 600;
    }
    .sw-alert__message {
      margin: 0 0 var(--sw-space-lg);
      color: var(--sw-text-muted);
    }
    .sw-alert__actions {
      display: flex;
      flex-wrap: wrap;
      justify-content: flex-end;
      gap: var(--sw-space-sm);
    }
    """)
}
