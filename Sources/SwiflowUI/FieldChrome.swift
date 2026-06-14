// Sources/SwiflowUI/FieldChrome.swift
//
// The shared, layout-NEUTRAL chrome for the form controls (TextField, Toggle,
// and the upcoming Select/RadioGroup). Each control lays its parts out
// differently — TextField/Select stack the label above the control, Toggle puts
// it beside, RadioGroup uses a fieldset/legend — but they all share: the input
// attribute assembly (aria + disabled + blur + caller merge), the error message
// node, and one token-only stylesheet. Extracted at the second consumer (Toggle)
// rather than abstracted speculatively on the first.
import Swiflow

/// Assembles a form-control element's attributes: the control-specific `base`
/// (`type` + `value`/`checked`), then `aria-invalid`, optional `aria-required`,
/// `disabled`, the optional blur handler, and the merged caller attributes
/// (applied last so they win on plain attrs). A caller `.class` merges; other
/// caller attrs append. Callers must NOT pass `.value`/`.on` for the bound event
/// — that would overwrite the binding's handler.
@MainActor
func controlInputAttributes(
    _ base: [Attribute],
    error: String?,
    required: Bool,
    disabled: Bool,
    onBlur: (@MainActor () -> Void)?,
    caller: [Attribute]
) -> [Attribute] {
    let (callerClasses, callerRest) = splitClasses(caller)
    var attrs = base
    attrs.append(.attr("aria-invalid", error != nil ? "true" : "false"))
    if required { attrs.append(.attr("aria-required", "true")) }  // a11y signal only; native `required` would fire its own validation
    if disabled { attrs.append(.attr("disabled", true)) }
    if let onBlur { attrs.append(.on(.blur, perform: onBlur)) }
    if !callerClasses.isEmpty { attrs.append(.class(callerClasses.joined(separator: " "))) }
    attrs += callerRest
    return attrs
}

/// The shared validation-error node (`role="alert"`, announced when it appears),
/// or `nil` when valid. Layout is the caller's job — this is just the message
/// element every control reuses.
func fieldErrorNode(_ error: String?) -> VNode? {
    guard let error else { return nil }
    return element("p", attributes: [.class("sw-field-error"), .attr("role", "alert")],
                   children: [text(error)])
}

/// Injects the shared form-controls stylesheet once (idempotent once-guard).
@MainActor
func installFieldStyles() { installControlSheet(id: "sw-forms", fieldStyleSheet) }

/// The one stylesheet for all form controls: the column-input chrome
/// (TextField/Select), the checkbox-row chrome (Toggle), and the shared error
/// message. Every value reads a `--sw-*` token, so the M2 media-feature layers
/// (reduced-motion via `--sw-duration`, contrast via `--sw-focus-ring`/
/// `--sw-border-width`, dark via `light-dark()`, p3) apply with no per-control code.
let fieldStyleSheet: CSSSheet = css {
    raw("""
    /* shared validation-error message */
    .sw-field-error {
      margin: 0;
      font-size: 0.8125rem;
      color: var(--sw-danger);
    }

    /* --- column inputs: TextField / Select (label above the control) --- */
    .sw-field { display: flex; flex-direction: column; gap: var(--sw-space-xs); }
    .sw-field__label {
      display: flex;
      flex-direction: column;
      gap: var(--sw-space-xs);
      font-size: 0.875rem;
      font-weight: 500;
      color: var(--sw-text);
    }
    .sw-field input,
    .sw-field select,
    .sw-field textarea {
      font: inherit;
      width: 100%;
      box-sizing: border-box;
      padding: var(--sw-space-sm) var(--sw-space-md);   /* fallback; the size modifier overrides */
      border: var(--sw-border-width) solid var(--sw-border);
      border-radius: var(--sw-radius);
      background-color: var(--sw-surface);
      color: var(--sw-text);
      transition: border-color var(--sw-duration) var(--sw-ease);
    }
    .sw-field input:focus-visible,
    .sw-field select:focus-visible,
    .sw-field textarea:focus-visible {
      outline: var(--sw-focus-ring-width) solid var(--sw-focus-ring);
      outline-offset: 2px;
      border-color: var(--sw-focus-ring);
    }
    .sw-field input:disabled,
    .sw-field select:disabled,
    .sw-field textarea:disabled {
      opacity: var(--sw-disabled-opacity);
      cursor: not-allowed;
    }
    .sw-field input[aria-invalid="true"],
    .sw-field select[aria-invalid="true"],
    .sw-field textarea[aria-invalid="true"] {
      border-color: var(--sw-danger);
    }
    .sw-field--sm input, .sw-field--sm select, .sw-field--sm textarea { padding: var(--sw-space-xs) var(--sw-space-sm); font-size: 0.875rem; }
    .sw-field--md input, .sw-field--md select, .sw-field--md textarea { padding: var(--sw-space-sm) var(--sw-space-md); font-size: 1rem; }
    .sw-field--lg input, .sw-field--lg select, .sw-field--lg textarea { padding: var(--sw-space-md) var(--sw-space-lg); font-size: 1.125rem; }

    /* --- Toggle: checkbox with the label BESIDE it --- */
    .sw-toggle { display: flex; flex-direction: column; gap: var(--sw-space-xs); }
    .sw-toggle__row {
      display: flex;
      flex-direction: row;
      align-items: center;
      gap: var(--sw-space-sm);
      color: var(--sw-text);
      cursor: pointer;
    }
    .sw-toggle input[type="checkbox"] {
      flex: none;
      width: 1.1em;
      height: 1.1em;
      accent-color: var(--sw-accent);
      cursor: pointer;
    }
    .sw-toggle input:focus-visible {
      outline: var(--sw-focus-ring-width) solid var(--sw-focus-ring);
      outline-offset: 2px;
    }
    .sw-toggle input[aria-invalid="true"] {
      outline: var(--sw-border-width) solid var(--sw-danger);
      outline-offset: 2px;
    }
    .sw-toggle__row:has(input:disabled) {
      opacity: var(--sw-disabled-opacity);
      cursor: not-allowed;
    }
    """)
}
