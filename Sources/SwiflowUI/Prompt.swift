// Sources/SwiflowUI/Prompt.swift
import Swiflow
#if canImport(JavaScriptKit)
import JavaScriptKit
#endif

/// A modal text-input dialog. Like `Alert`, but with a single bound text field and a
/// confirm/cancel pair, built on a native `<dialog>.showModal()` + an inner
/// `<form method="dialog">` so **Enter submits** and ESC/Cancel dismiss without
/// submitting. `onSubmit` fires only on confirm (Enter or the confirm button) — never
/// on Cancel or ESC. The `text` binding pre-fills the field and round-trips the value.
///
///     @State var name = "untitled"
///     @State var showRename = false
///     …
///     Button("Rename…") { showRename = true }
///     Prompt("Rename file", isPresented: $showRename, text: $name,
///            message: "Enter a new name", placeholder: "untitled",
///            confirmTitle: "Rename") { newName in rename(to: newName) }
///
/// The input is a SwiflowUI `TextField`, so it carries the same token styling and
/// implicit `<label>` association as every other field; `message` becomes that label
/// (falling back to `title` if omitted, so the input is always labelled).
///
/// > Note: like `Alert`, `title`/`message`/button titles/`onSubmit` update LIVE —
/// > pushed into the reused dialog on every parent re-render. `key:` remains for
/// > deliberate remounts.
///
/// Set `dismissOnBackdrop: true` to cancel (close without `onSubmit`) on a backdrop
/// click, in addition to ESC + Cancel. Off by default.
@MainActor
public func Prompt(
    _ title: String,
    isPresented: Binding<Bool>,
    text: Binding<String>,
    message: String? = nil,
    placeholder: String = "",
    confirmTitle: String = "OK",
    cancelTitle: String = "Cancel",
    dismissOnBackdrop: Bool = false,
    key: String? = nil,
    onSubmit: @escaping (String) -> Void
) -> VNode {
    embedKeyed(key, {
        PromptDialog(title: title, isPresented: isPresented, text: text, message: message,
                     placeholder: placeholder, confirmTitle: confirmTitle,
                     cancelTitle: cancelTitle, dismissOnBackdrop: dismissOnBackdrop, onSubmit: onSubmit)
    }, refresh: { dialog in
        // Thread the display props LIVE (audit V Wave-2 #6); the
        // isPresented/text Bindings were always live.
        dialog.title = title
        dialog.message = message
        dialog.placeholder = placeholder
        dialog.confirmTitle = confirmTitle
        dialog.cancelTitle = cancelTitle
        dialog.onSubmit = onSubmit
        dialog.host.dismissOnBackdrop = dismissOnBackdrop
    })
}

/// The stateful implementation behind `Prompt`. Mirrors `AlertDialog`'s `<dialog>`
/// open/close sync; adds the `<form method="dialog">` submit path.
@Component
final class PromptDialog {
    var title: String
    var message: String?
    var placeholder: String
    var confirmTitle: String
    var cancelTitle: String
    private let isPresented: Binding<Bool>   // kept for the form's confirm/cancel closures
    private let textBinding: Binding<String>   // not `text` — that would shadow the text(_:) node factory
    var onSubmit: (String) -> Void
    private let titleID: String
    /// The shared modal machinery: ref, open/close sync, guarded close
    /// handler, backdrop dismissal (a CANCEL here — never submits), scaffold.
    var host: ModalDialogHost

    init(title: String, isPresented: Binding<Bool>, text: Binding<String>, message: String?,
         placeholder: String, confirmTitle: String, cancelTitle: String,
         dismissOnBackdrop: Bool = false, onSubmit: @escaping (String) -> Void) {
        self.title = title
        self.isPresented = isPresented
        self.textBinding = text
        self.message = message
        self.placeholder = placeholder
        self.confirmTitle = confirmTitle
        self.cancelTitle = cancelTitle
        self.onSubmit = onSubmit
        self.titleID = nextSwID("sw-prompt-title")
        self.host = ModalDialogHost(isPresented: isPresented, dismissOnBackdrop: dismissOnBackdrop)
    }

    var body: VNode {
        ensureBaseStyles()
        installDialogChrome()
        installControlSheet(id: "sw-prompt", promptStyleSheet)

        // The prompt text labels the input (implicit <label> association via TextField).
        let fieldLabel = message ?? title

        let formNode = element("form",
            attributes: [
                .class("sw-prompt__form"),
                .attr("method", "dialog"),     // submit closes the dialog natively — never navigates
                // Enter (implicit single-input submit) OR the confirm button (type=submit) fire this;
                // Cancel (type=button) and ESC do NOT, so onSubmit means "confirmed". The text is read
                // from the binding, not the event — on a submit event evt.target is the <form> (no value).
                // method="dialog" performs the visual close natively; set(false) just reconciles the binding.
                .on(.submit) { self.onSubmit(self.textBinding.get()); self.isPresented.set(false) },
            ],
            children: [
                // autofocus so the field is ready to type on open; showModal() honors it.
                TextField(fieldLabel, text: textBinding, placeholder: placeholder, .attr("autofocus", true)),
                element("div", attributes: [.class("sw-dialog__actions")], children: [
                    Button(cancelTitle, variant: .secondary) { self.isPresented.set(false) },
                    Button(confirmTitle, type: .submit),   // the form's submit is the single source of truth
                ]),
            ])

        return host.dialogNode(
            kindClass: "sw-prompt",
            // dialog name = the <h2>; the input is named by its own wrapping <label> (TextField).
            extra: [.attr("aria-labelledby", titleID)],
            bodyChildren: [
                element("h2", attributes: [.class("sw-dialog__title"), .attr("id", titleID)], children: [text(title)]),
                formNode,
            ])
    }

    func onAppear() { host.syncOpenState() }
    func onChange() { host.syncOpenState() }
}

/// Just the prompt-specific layout — the chrome (surface/animation/backdrop/title/
/// actions) comes from `dialogChromeSheet`. Stacks the field above the actions.
let promptStyleSheet: CSSSheet = css {
    raw("""
    .sw-prompt__form {
      display: flex;
      flex-direction: column;
      gap: var(--sw-space-md);
      margin: 0;
    }
    """)
}
