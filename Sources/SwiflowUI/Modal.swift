// Sources/SwiflowUI/Modal.swift
import Swiflow
#if canImport(JavaScriptKit)
import JavaScriptKit
#endif

/// The size variant of a `Modal`'s card. `.md` is the chrome default (`28rem`, see
/// `DialogChrome.swift`) — it emits no modifier class of its own; `.sm`/`.lg` add a
/// `.sw-modal--sm`/`.sw-modal--lg` rule that overrides the max-width.
public enum ModalSize {
    case sm, md, lg

    var modifierClass: String {
        switch self {
        case .sm: return "sm"
        case .md: return "md"
        case .lg: return "lg"
        }
    }
}

/// A general-purpose modal dialog. Where `Alert`/`Prompt` bake in a specific shape
/// (a required title + message/actions, or a title + single text field), `Modal` is
/// the escape hatch: an optional title and arbitrary content, for anything from a
/// settings panel to a multi-field form. Built on the same native `<dialog>` driven
/// by `showModal()`/`close()` as Alert/Prompt (top layer, backdrop, focus trap,
/// ESC-to-close, all native) — see `ModalDialogHost`.
///
/// Returns an embedded component, so it can sit directly in a parent's `body`:
///
///     @State var showSettings = false
///     …
///     Button("Settings…") { showSettings = true }
///     Modal(isPresented: $showSettings, title: "Settings", size: .lg) {
///         // any content — fields, sections, whatever the caller needs
///         Button("Close") { showSettings = false }
///     }
///
/// > Note: `title`/`size`/`content`/`dismissOnBackdrop` update LIVE — the facade
/// > pushes them into the reused dialog on every parent re-render. `key:` remains
/// > available when you want a full remount instead (fresh entry animation, reset
/// > internal state).
///
/// `dismissOnBackdrop` defaults to `true` here — the opposite of Alert's `false`.
/// An alert demands a deliberate response (so accidental backdrop-dismissal is
/// usually unwanted); a generic modal is more often a casual overlay (a settings
/// panel, a details sheet) where clicking outside to leave is the expected,
/// low-stakes affordance. Set it to `false` when the modal guards unsaved work or
/// otherwise needs a deliberate exit.
@MainActor
public func Modal(
    isPresented: Binding<Bool>,
    title: String? = nil,
    size: ModalSize = .md,
    dismissOnBackdrop: Bool = true,
    key: String? = nil,
    @ChildrenBuilder content: @escaping () -> [VNode]
) -> VNode {
    embedKeyed(key, {
        ModalDialog(isPresented: isPresented, title: title, size: size,
                    dismissOnBackdrop: dismissOnBackdrop, content: content)
    }, refresh: { dialog in
        // Thread the display props LIVE into the reused instance, mirroring
        // Alert/Prompt (audit V Wave-2 #6) — isPresented stays init-bound: it's a
        // Binding, already live.
        dialog.title = title
        dialog.size = size
        dialog.content = content
        dialog.host.dismissOnBackdrop = dismissOnBackdrop
    })
}

/// The stateful implementation behind `Modal`. A `@Component` because a *modal*
/// dialog needs the imperative `showModal()` (the `open` attribute alone is
/// non-modal) — synced to `isPresented` in `onChange`/`onAppear`, exactly like
/// `AlertDialog`/`PromptDialog`. The JS-interop bits live in `ModalDialogHost`,
/// `#if`-gated so the dialog structure still builds + unit-tests on host.
@Component
final class ModalDialog {
    var title: String?
    var size: ModalSize
    var content: () -> [VNode]
    // Stable id for the optional title's ARIA wiring, captured once at init (not
    // per body) so it's stable across re-renders and never collides between two
    // instances — even though only one of them ever gets used per render (no
    // title → the id is simply unused).
    private let titleID: String
    /// The shared modal machinery: ref, open/close sync, guarded close
    /// handler, backdrop dismissal, scaffold. See `ModalDialogHost`.
    var host: ModalDialogHost

    init(isPresented: Binding<Bool>, title: String? = nil, size: ModalSize = .md,
         dismissOnBackdrop: Bool = true, content: @escaping () -> [VNode]) {
        self.title = title
        self.size = size
        self.content = content
        self.titleID = nextSwID("sw-modal-title")
        self.host = ModalDialogHost(isPresented: isPresented, dismissOnBackdrop: dismissOnBackdrop)
    }

    var body: VNode {
        ensureBaseStyles()
        installDialogChrome()

        // No `role` — a generic modal keeps the native `dialog` role (unlike
        // Alert's `alertdialog`, which asserts "this requires a response").
        var extra: [Attribute] = []
        if title != nil { extra.append(.attr("aria-labelledby", titleID)) }

        var bodyChildren: [VNode] = []
        if let title {
            bodyChildren.append(element("h2", attributes: [.class("sw-dialog__title"), .attr("id", titleID)],
                                        children: [text(title)]))
        }
        bodyChildren += content()

        return host.dialogNode(kindClass: "sw-modal sw-modal--\(size.modifierClass)", extra: extra,
                               bodyChildren: bodyChildren)
    }

    func onAppear() { host.syncOpenState() }
    func onChange() { host.syncOpenState() }
}
