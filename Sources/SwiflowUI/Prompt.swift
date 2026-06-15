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
/// > Note: like `Alert`, `title`/`message`/button titles are captured at first
/// > presentation (the component is `embed`-reused; the `isPresented`/`text` bindings
/// > stay live). Key the embed yourself if you need that chrome to change while mounted.
@MainActor
/// Set `dismissOnBackdrop: true` to cancel (close without `onSubmit`) on a backdrop
/// click, in addition to ESC + Cancel. Off by default.
public func Prompt(
    _ title: String,
    isPresented: Binding<Bool>,
    text: Binding<String>,
    message: String? = nil,
    placeholder: String = "",
    confirmTitle: String = "OK",
    cancelTitle: String = "Cancel",
    dismissOnBackdrop: Bool = false,
    onSubmit: @escaping (String) -> Void
) -> VNode {
    embed {
        PromptDialog(title: title, isPresented: isPresented, text: text, message: message,
                     placeholder: placeholder, confirmTitle: confirmTitle,
                     cancelTitle: cancelTitle, dismissOnBackdrop: dismissOnBackdrop, onSubmit: onSubmit)
    }
}

/// The stateful implementation behind `Prompt`. Mirrors `AlertDialog`'s `<dialog>`
/// open/close sync; adds the `<form method="dialog">` submit path.
@MainActor @Component
final class PromptDialog {
    private let title: String
    private let message: String?
    private let placeholder: String
    private let confirmTitle: String
    private let cancelTitle: String
    private let isPresented: Binding<Bool>
    private let textBinding: Binding<String>   // not `text` — that would shadow the text(_:) node factory
    private let onSubmit: (String) -> Void
    private let dismissOnBackdrop: Bool
    private let titleID: String
    #if canImport(JavaScriptKit)
    private let dialogRef = Ref<JSObject>()
    #endif

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
        self.dismissOnBackdrop = dismissOnBackdrop
        self.onSubmit = onSubmit
        self.titleID = nextSwID("sw-prompt-title")
    }

    var body: VNode {
        ensureBaseStyles()
        installDialogChrome()
        installControlSheet(id: "sw-prompt", promptStyleSheet)

        var attrs: [Attribute] = [
            .class("sw-dialog sw-prompt"),
            // dialog name = the <h2>; the input is named by its own wrapping <label> (TextField).
            .attr("aria-labelledby", titleID),
            // ESC closes natively → keep the binding in sync (guarded so we don't echo our own close).
            .on(.custom("close")) { if self.isPresented.get() { self.isPresented.set(false) } },
        ]
        if dismissOnBackdrop {
            // Backdrop click (targets the <dialog> itself) cancels — never calls onSubmit.
            // Content clicks target a child (the body/form), so they don't dismiss.
            attrs.append(.on(.click) { if $0.isSelfTarget { self.isPresented.set(false) } })
        }
        #if canImport(JavaScriptKit)
        attrs.append(.refBinding(AnyRefBinding(dialogRef)))
        #endif

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

        // Inner body carries the padding (DialogChrome) so the dialog box coincides
        // with it — keeping a backdrop click the only self-target for dismiss-on-tap.
        let bodyNode = element("div", attributes: [.class("sw-dialog__body")], children: [
            element("h2", attributes: [.class("sw-dialog__title"), .attr("id", titleID)], children: [text(title)]),
            formNode,
        ])
        return element("dialog", attributes: attrs, children: [bodyNode])
    }

    func onAppear() { syncOpenState() }
    func onChange() { syncOpenState() }

    /// Identical contract to `AlertDialog.syncOpenState` — idempotent read-diff-write,
    /// safe under the global per-render `onChange` firing; no-ops on host (nil ref).
    private func syncOpenState() {
        #if canImport(JavaScriptKit)
        guard let el = dialogRef.wrappedValue else { return }
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
