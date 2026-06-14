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
/// caller attrs append.
///
/// FOOTGUN: callers must NOT pass the binding's own event handler — `.value` /
/// `.on(.input)` for text inputs, `.checked` / `.on(.change)` for Toggle/Select.
/// `callerRest` applies last and handlers are last-write-wins per event key, so a
/// duplicate would silently overwrite the binding's write-back. Drive the value
/// through the control's `text:`/`isOn:`/`field:` parameter instead.
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

/// Group-level attributes for a fieldset-based control (RadioGroup): the merged
/// root class, the GROUP's `aria-invalid`/`aria-required`, and native `disabled`
/// (a disabled `<fieldset>` disables every control inside it). The per-OPTION
/// radios get their own simple assembly — group aria lives here, on the fieldset,
/// not on each radio. The group analog of `controlInputAttributes`: single-input
/// controls put aria on their one input; a group puts it on the fieldset.
@MainActor
func fieldGroupAttributes(
    _ baseClasses: [String],
    error: String?,
    required: Bool,
    disabled: Bool,
    caller: [Attribute]
) -> [Attribute] {
    let (callerClasses, callerRest) = splitClasses(caller)
    var attrs: [Attribute] = [.class((baseClasses + callerClasses).joined(separator: " "))]
    attrs.append(.attr("aria-invalid", error != nil ? "true" : "false"))
    if required { attrs.append(.attr("aria-required", "true")) }
    if disabled { attrs.append(.attr("disabled", true)) }   // native <fieldset disabled> cascades
    attrs += callerRest
    return attrs
}

/// Injects the shared form-controls stylesheet once (idempotent once-guard).
@MainActor
func installFieldStyles() { installControlSheet(id: "sw-forms", formControlsSheet) }

/// The one stylesheet for all form controls: the column-input chrome
/// (TextField/Select), the checkbox-row chrome (Toggle), and the shared error
/// message. Every value reads a `--sw-*` token, so the M2 media-feature layers
/// (reduced-motion via `--sw-duration`, contrast via `--sw-focus-ring`/
/// `--sw-border-width`, dark via `light-dark()`, p3) apply with no per-control code.
/// Keep each control's selector root (`.sw-field` vs `.sw-toggle`) disjoint so the
/// shared blob can't cross-style layouts.
let formControlsSheet: CSSSheet = css {
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

    /* --- Select: skinnable native <select> --- */
    /* Fallback (all browsers): strip native chrome, draw a chevron. The base
       rules above already give border/radius/surface/padding/focus/disabled. */
    .sw-field select {
      appearance: none;
      background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16' fill='none' stroke='%23888' stroke-width='1.5' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M4 6l4 4 4-4'/%3E%3C/svg%3E");
      background-repeat: no-repeat;
      background-position: right var(--sw-space-md) center;
      background-size: 1em;
      padding-right: calc(var(--sw-space-md) * 2 + 1em);
    }
    /* Modern (Customizable Select, 2024+): style the control AND its dropdown
       picker, fully token-driven. Gated on @supports so older browsers keep the
       fallback above (and the native, unstyled option popup). */
    @supports (appearance: base-select) {
      .sw-field select,
      .sw-field ::picker(select) { appearance: base-select; }
      .sw-field select {
        background-image: none;            /* base-select supplies ::picker-icon */
        padding-right: var(--sw-space-md);
      }
      .sw-field select::picker-icon {
        color: var(--sw-text-muted);
        transition: transform var(--sw-duration) var(--sw-ease);
      }
      .sw-field select:open::picker-icon { transform: rotate(180deg); }
      .sw-field ::picker(select) {
        background-color: var(--sw-surface);
        border: var(--sw-border-width) solid var(--sw-border);
        border-radius: var(--sw-radius);
        padding: var(--sw-space-xs);
        box-shadow: 0 4px 12px rgb(0 0 0 / 0.12);
      }
      .sw-field option {
        display: flex;
        align-items: center;
        gap: var(--sw-space-sm);
        padding: var(--sw-space-sm) var(--sw-space-md);
        border-radius: var(--sw-radius-sm);
      }
      .sw-field option:hover { background-color: var(--sw-surface-2); }
      .sw-field option:checked { color: var(--sw-accent); }
      .sw-field option::checkmark { color: var(--sw-accent); }
    }

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
    .sw-toggle__row--disabled {
      opacity: var(--sw-disabled-opacity);
      cursor: not-allowed;
    }

    /* --- RadioGroup: <fieldset>/<legend> + native radios (shared name = roving focus) --- */
    .sw-radio {
      display: flex;
      flex-direction: column;
      gap: var(--sw-space-xs);
      border: none;            /* reset the native fieldset chrome */
      margin: 0;
      padding: 0;
      min-width: 0;
    }
    .sw-radio__legend {
      padding: 0;
      font-size: 0.875rem;
      font-weight: 500;
      color: var(--sw-text);
      margin-bottom: var(--sw-space-xs);
    }
    .sw-radio__option {
      display: flex;
      flex-direction: row;
      align-items: center;
      gap: var(--sw-space-sm);
      color: var(--sw-text);
      cursor: pointer;
    }
    .sw-radio input[type="radio"] {
      flex: none;
      width: 1.1em;
      height: 1.1em;
      accent-color: var(--sw-accent);
      cursor: pointer;
    }
    .sw-radio input:focus-visible {
      outline: var(--sw-focus-ring-width) solid var(--sw-focus-ring);
      outline-offset: 2px;
    }
    /* The group has no single input to mark, so signal the error on the legend. */
    .sw-radio[aria-invalid="true"] .sw-radio__legend { color: var(--sw-danger); }
    .sw-radio:disabled .sw-radio__option {
      opacity: var(--sw-disabled-opacity);
      cursor: not-allowed;
    }
    """)
}
