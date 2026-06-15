// Sources/SwiflowUI/DialogChrome.swift
import Swiflow

/// Shared chrome for the modal `<dialog>` overlays (Alert, Prompt): centering,
/// sizing, surface, elevation, the `@starting-style` entry + `allow-discrete` exit
/// animation, the `::backdrop`, and the common title/message/actions slots. Both
/// overlays carry `class="sw-dialog …"`, so these unscoped `.sw-dialog` rules apply;
/// each adds only its own content-specific bits (Alert: nothing; Prompt: the form).
///
/// `@starting-style` + `transition-behavior: allow-discrete` are Baseline 2024
/// (Chrome 117+, Safari 17.4+, Firefox 129+). On older engines the dialog still
/// *functions* — `showModal()` works — it just snaps open/closed without the
/// transition. Graceful degradation, intentional floor.
///
/// Backdrop reads the M2 overlay tokens, so reduced-transparency solidifies it;
/// transitions read `--sw-duration`, so reduced-motion collapses the animation.
let dialogChromeSheet: CSSSheet = css {
    raw("""
    .sw-dialog {
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
    .sw-dialog[open] {
      opacity: 1;
      transform: translateY(0) scale(1);
    }
    @starting-style {
      .sw-dialog[open] { opacity: 0; transform: translateY(8px) scale(0.98); }
    }
    .sw-dialog::backdrop {
      background-color: var(--sw-overlay-bg);
      -webkit-backdrop-filter: var(--sw-backdrop);
      backdrop-filter: var(--sw-backdrop);
    }
    .sw-dialog__title {
      margin: 0 0 var(--sw-space-sm);
      font-size: 1.125rem;
      font-weight: 600;
    }
    .sw-dialog__message {
      margin: 0 0 var(--sw-space-lg);
      color: var(--sw-text-muted);
    }
    .sw-dialog__actions {
      display: flex;
      flex-wrap: wrap;
      justify-content: flex-end;
      gap: var(--sw-space-sm);
    }
    """)
}

/// Installs `dialogChromeSheet` once. Called from Alert/Prompt `body`.
@MainActor
func installDialogChrome() { installControlSheet(id: "sw-dialog", dialogChromeSheet) }
