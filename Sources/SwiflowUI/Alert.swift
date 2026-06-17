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
/// > you genuinely need the content to change while mounted, pass a `key:` that
/// > changes with the content (e.g. `key: title`).
///
/// Set `dismissOnBackdrop: true` to also close when the user clicks the backdrop
/// (outside the card). Off by default — an alert asks for a deliberate response, so
/// accidental backdrop-dismissal is usually unwanted; opt in for casual alerts.
@MainActor
public func Alert(
    _ title: String,
    isPresented: Binding<Bool>,
    message: String? = nil,
    dismissOnBackdrop: Bool = false,
    key: String? = nil,
    @ChildrenBuilder actions: @escaping () -> [VNode]
) -> VNode {
    embedKeyed(key) {
        AlertDialog(title: title, isPresented: isPresented, message: message,
                    dismissOnBackdrop: dismissOnBackdrop, actions: actions)
    }
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
    private let dismissOnBackdrop: Bool
    private let actions: () -> [VNode]
    // Stable ids for ARIA wiring, captured once at init (not per body) so they're
    // stable across re-renders and never collide between two instances.
    private let titleID: String
    private let messageID: String
    #if canImport(JavaScriptKit)
    private let dialogRef = Ref<JSObject>()
    #endif

    init(title: String, isPresented: Binding<Bool>, message: String? = nil,
         dismissOnBackdrop: Bool = false, actions: @escaping () -> [VNode]) {
        self.title = title
        self.isPresented = isPresented
        self.message = message
        self.dismissOnBackdrop = dismissOnBackdrop
        self.actions = actions
        self.titleID = nextSwID("sw-alert-title")
        self.messageID = nextSwID("sw-alert-msg")
    }

    var body: VNode {
        ensureBaseStyles()
        installDialogChrome()

        var attrs: [Attribute] = [
            .class("sw-dialog sw-alert"),                 // shared modal chrome + internal alert marker
            .attr("role", "alertdialog"),                 // an alert that requires a response
            .attr("aria-labelledby", titleID),            // name = the visible <h2> (stays in sync)
            // Native close (ESC, close(), or a form method=dialog) → sync the binding back.
            // Guarded: this handler exists for *user*-driven closes; when we drive the close
            // ourselves (binding went false → syncOpenState calls close()), the native `close`
            // event still fires, and writing an already-false binding would schedule a wasted render.
            .on(.custom("close")) { if self.isPresented.get() { self.isPresented.set(false) } },
        ]
        if message != nil { attrs.append(.attr("aria-describedby", messageID)) }  // description = the message
        if dismissOnBackdrop {
            // A backdrop click targets the <dialog> itself (isSelfTarget); a click on
            // the .sw-dialog__body or its content targets a child, so this only fires
            // for true backdrop clicks. ESC + the action buttons still close it too.
            attrs.append(.on(.click) { if $0.isSelfTarget { self.isPresented.set(false) } })
        }
        #if canImport(JavaScriptKit)
        attrs.append(.refBinding(AnyRefBinding(dialogRef)))
        #endif

        var bodyChildren: [VNode] = [
            element("h2", attributes: [.class("sw-dialog__title"), .attr("id", titleID)], children: [text(title)]),
        ]
        if let message {
            bodyChildren.append(element("p", attributes: [.class("sw-dialog__message"), .attr("id", messageID)], children: [text(message)]))
        }
        bodyChildren.append(element("div", attributes: [.class("sw-dialog__actions")], children: actions()))
        // Inner body holds the padding (see DialogChrome) so the dialog box coincides
        // with it — that's what keeps a backdrop click the only self-target.
        let bodyNode = element("div", attributes: [.class("sw-dialog__body")], children: bodyChildren)
        return element("dialog", attributes: attrs, children: [bodyNode])
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

// Alert has no chrome of its own — it renders the shared `.sw-dialog` slots
// (`__title`/`__message`/`__actions`, see `DialogChrome.swift`). The `sw-alert`
// class is a SwiflowUI-internal semantic marker — it distinguishes an alert from a
// prompt dialog in the DOM and reserves a seam for SwiflowUI's own future variant
// rules (e.g. a destructive-alert treatment). It is NOT an app override hook: apps
// don't author `sw-*` CSS (that prefix is reserved — see ControlClass.swift).
