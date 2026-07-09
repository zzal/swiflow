// Sources/SwiflowUI/ModalDialogHost.swift
import Swiflow
#if canImport(JavaScriptKit)
import JavaScriptKit
#endif

/// The shared machinery of a native modal `<dialog>` driven by an
/// `isPresented` binding — extracted from `AlertDialog`/`PromptDialog`,
/// whose copies had already been flagged as byte-identical-but-drifting
/// (audit V Wave-2 #2: consolidate BEFORE drift; sibling-inconsistency is
/// the audit's dominant defect shape). Owned as a stored property by each
/// dialog `@Component` — NOT a component itself: the owner keeps the
/// lifecycle (`onAppear`/`onChange`) and forwards to `syncOpenState()`;
/// this struct keeps the ref, the sync contract, and the shared attribute
/// + scaffold construction in ONE place.
@MainActor
struct ModalDialogHost {
    let isPresented: Binding<Bool>
    /// `var`: threaded LIVE by the owning facade's `refresh:` push (audit V
    /// Wave-2 #6). Mutating this sibling field never touches `dialogRef` —
    /// the Ref is a class reference; the struct mutation leaves it intact.
    var dismissOnBackdrop: Bool
    #if canImport(JavaScriptKit)
    let dialogRef = Ref<JSObject>()
    #endif

    init(isPresented: Binding<Bool>, dismissOnBackdrop: Bool) {
        self.isPresented = isPresented
        self.dismissOnBackdrop = dismissOnBackdrop
    }

    /// Build the `<dialog>` element: shared chrome class + the guarded
    /// native-close sync + opt-in backdrop dismissal + the ref binding,
    /// then the dialog-specific `extra` attributes (role, ARIA wiring),
    /// with `bodyChildren` wrapped in the padded `.sw-dialog__body` (the
    /// body carries the padding — see DialogChrome — so the dialog box
    /// coincides with it, keeping a backdrop click the only self-target).
    func dialogNode(kindClass: String, extra: [Attribute], bodyChildren: [VNode]) -> VNode {
        var attrs: [Attribute] = [
            .class("sw-dialog \(kindClass)"),
            // Native close (ESC, close(), or a form method=dialog) → sync the
            // binding back. Guarded: this handler exists for USER-driven
            // closes; when we drive the close ourselves (binding went false →
            // syncOpenState calls close()), the native `close` event still
            // fires, and writing an already-false binding would schedule a
            // wasted render.
            .on(.custom("close")) { if self.isPresented.get() { self.isPresented.set(false) } },
        ]
        if dismissOnBackdrop {
            // A backdrop click targets the <dialog> itself (isSelfTarget); a
            // click on the .sw-dialog__body or its content targets a child,
            // so this only fires for true backdrop clicks. For a prompt this
            // is a CANCEL — it never submits.
            attrs.append(.on(.click) { if $0.isSelfTarget { self.isPresented.set(false) } })
        }
        attrs += extra
        #if canImport(JavaScriptKit)
        attrs.append(.refBinding(AnyRefBinding(dialogRef)))
        #endif
        let bodyNode = element("div", attributes: [.class("sw-dialog__body")], children: bodyChildren)
        return element("dialog", attributes: attrs, children: [bodyNode])
    }

    /// Drive the native modal state from `isPresented`.
    ///
    /// Read-diff-write, deliberately idempotent: `onChange` fires after *every* app
    /// render (the framework walks the whole committed tree post-render, not just
    /// changed components), so this runs constantly — the `el.open` diff guard is what
    /// makes that safe and cheap. Do NOT "optimize" the guard away. `onAppear` runs
    /// post-commit (ref handles are set at element mount, before this lifecycle pass),
    /// so the `<dialog>` is guaranteed resolved here — an `isPresented: true`-at-mount
    /// dialog opens correctly. `showModal()`/`close()` set `.open` synchronously; the
    /// native `close` event is queued as a separate task, so there's no re-entrancy here.
    func syncOpenState() {
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
