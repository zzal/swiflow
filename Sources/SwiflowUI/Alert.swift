// Sources/SwiflowUI/Alert.swift
import Swiflow
#if canImport(JavaScriptKit)
import JavaScriptKit
#endif

/// A modal alert dialog. SwiftUI-style declarative API: bind `isPresented` and the
/// alert opens/closes to match. Built on a native `<dialog>` driven by
/// `showModal()`/`close()` (so it's a true modal — top layer, backdrop, focus trap,
/// ESC-to-close, all native), with token-driven styling and `@starting-style` entry
/// animation. Dismissal is ESC + the action buttons you provide, plus an opt-in
/// backdrop click (`dismissOnBackdrop:`, via `EventInfo.isSelfTarget`); the native
/// `close` event (incl. ESC) writes `isPresented` back to `false`.
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
/// > Note: `title`/`message`/`actions` (and `dismissOnBackdrop`) update LIVE —
/// > the facade pushes them into the reused dialog on every parent re-render,
/// > so interpolated titles just work. `key:` remains available when you want a
/// > full remount instead (fresh entry animation, reset internal state).
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
    embedKeyed(key, {
        AlertDialog(title: title, isPresented: isPresented, message: message,
                    dismissOnBackdrop: dismissOnBackdrop, actions: actions)
    }, refresh: { dialog in
        // Thread the display props LIVE into the reused instance. isPresented
        // stays init-bound: it's a Binding, already live.
        dialog.title = title
        dialog.message = message
        dialog.actions = actions
        dialog.host.dismissOnBackdrop = dismissOnBackdrop
    })
}

/// The stateful implementation behind `Alert`. A `@Component` because a *modal*
/// dialog needs the imperative `showModal()` (the `open` attribute alone is
/// non-modal) — synced to `isPresented` in `onChange`/`onAppear`. The JS-interop
/// bits are `#if`-gated so the dialog structure still builds + unit-tests on host.
@Component
final class AlertDialog {
    var title: String
    var message: String?
    var actions: () -> [VNode]
    // Stable ids for ARIA wiring, captured once at init (not per body) so they're
    // stable across re-renders and never collide between two instances.
    private let titleID: String
    private let messageID: String
    /// The shared modal machinery: ref, open/close sync, guarded close
    /// handler, backdrop dismissal, scaffold. See `ModalDialogHost`.
    var host: ModalDialogHost

    init(title: String, isPresented: Binding<Bool>, message: String? = nil,
         dismissOnBackdrop: Bool = false, actions: @escaping () -> [VNode]) {
        self.title = title
        self.message = message
        self.actions = actions
        self.titleID = nextSwID("sw-alert-title")
        self.messageID = nextSwID("sw-alert-msg")
        self.host = ModalDialogHost(isPresented: isPresented, dismissOnBackdrop: dismissOnBackdrop)
    }

    var body: VNode {
        ensureBaseStyles()
        installDialogChrome()

        var extra: [Attribute] = [
            .attr("role", "alertdialog"),                 // an alert that requires a response
            .attr("aria-labelledby", titleID),            // name = the visible <h2> (stays in sync)
        ]
        if message != nil { extra.append(.attr("aria-describedby", messageID)) }  // description = the message

        var bodyChildren: [VNode] = [
            element("h2", attributes: [.class("sw-dialog__title"), .attr("id", titleID)], children: [text(title)]),
        ]
        if let message {
            bodyChildren.append(element("p", attributes: [.class("sw-dialog__message"), .attr("id", messageID)], children: [text(message)]))
        }
        bodyChildren.append(element("div", attributes: [.class("sw-dialog__actions")], children: actions()))
        // `sw-alert` is the SwiflowUI-internal semantic marker (see note below).
        return host.dialogNode(kindClass: "sw-alert", extra: extra, bodyChildren: bodyChildren)
    }

    func onAppear() { host.syncOpenState() }
    func onChange() { host.syncOpenState() }
}

// Alert has no chrome of its own — it renders the shared `.sw-dialog` slots
// (`__title`/`__message`/`__actions`, see `DialogChrome.swift`). The `sw-alert`
// class is a SwiflowUI-internal semantic marker — it distinguishes an alert from a
// prompt dialog in the DOM and reserves a seam for SwiflowUI's own future variant
// rules (e.g. a destructive-alert treatment). It is NOT an app override hook: apps
// don't author `sw-*` CSS (that prefix is reserved — see ControlClass.swift).
