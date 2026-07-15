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

#if DEBUG
/// Enforces the FOOTGUN documented on `controlInputAttributes`/`fieldGroupAttributes`:
/// a caller must not reach past the `text:`/`isOn:`/`field:` parameter and drive the
/// control's value through the trailing attribute bag. `.value`/`.checked` desugar to a
/// `value`/`checked` *property* write and `.on(.input)`/`.on(.change)` to an `input`/
/// `change` *handler* — both land in the same last-write-wins bag as the binding the
/// control installs, so a duplicate silently clobbers the binding's write-back. Fires a
/// `swiflowDiagnostic` (a DEBUG `preconditionFailure`, no-op in release) so the mistake is
/// loud in development instead of a silently dead control. Recurses into `.compound` so a
/// reserved effect nested in a composite modifier is caught too.
@MainActor
func assertNoReservedBindingAttributes(_ attributes: [Attribute]) {
    for attribute in attributes {
        switch attribute {
        case let .property(name, _) where name == "value" || name == "checked":
            swiflowDiagnostic("SwiflowUI form control: a `\(name)` binding (`.value`/`.checked`) was passed through the trailing attributes. The control owns its value — drive it through the `text:`/`isOn:`/`field:` parameter; a duplicate silently overwrites the binding's write-back.")
        case let .handler(event, _) where event == "input" || event == "change":
            swiflowDiagnostic("SwiflowUI form control: an `\(event)` handler (`.on(.\(event))`) was passed through the trailing attributes. The control's value binding already handles `\(event)` and is last-write-wins, so a duplicate silently overwrites its write-back. Drive the value through the `text:`/`isOn:`/`field:` parameter (use `onBlur:` for side effects).")
        case let .compound(inner):
            assertNoReservedBindingAttributes(inner)
        default:
            break
        }
    }
}
#endif

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
/// through the control's `text:`/`isOn:`/`field:` parameter instead. DEBUG builds
/// enforce this — see `assertNoReservedBindingAttributes`.
@MainActor
func controlInputAttributes(
    _ base: [Attribute],
    error: String?,
    required: Bool,
    disabled: Bool,
    onBlur: (@MainActor () -> Void)?,
    caller: [Attribute]
) -> [Attribute] {
    #if DEBUG
    assertNoReservedBindingAttributes(caller)
    #endif
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
    #if DEBUG
    assertNoReservedBindingAttributes(caller)
    #endif
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

/// Trims a trailing `.0` off a whole-number `Double` (`0` → `"0"`, not
/// `"0.0"`), so e.g. `min: 0` emits `min="0"`. Falls back to `String(v)` for
/// fractional values or magnitudes beyond exact `Int` round-tripping. Shared
/// by `NumberField` (min/max/step) and `Slider` (range bounds/step) — extracted
/// here at the second consumer rather than duplicated.
func formatControlNumber(_ v: Double) -> String {
    v == v.rounded() && v.magnitude < 1e15 ? String(Int(v)) : String(v)
}

/// The "expand more" chevron as an inline SVG data-URI, at a given `stroke`. One geometry
/// (path + width) is the single source of truth for the chevron everywhere it appears.
/// `swChevronDownSVG` (currentColor) feeds the *masks*: the Select `::picker-icon` and the
/// Dropdown caret each fill a box with `var(--sw-text-muted)` and clip it to this shape, so
/// they're token-colored and dark-adaptive. The fallback `<select>` (no Customizable Select)
/// can't mask, so it bakes the muted color into the SVG and swaps light/dark via `light-dark()`.
func chevronDownSVG(stroke: String) -> String {
    "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='16' height='16' viewBox='0 0 16 16' fill='none' stroke='\(stroke)' stroke-width='1.75' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M4 6l4 4 4-4'/%3E%3C/svg%3E"
}
let swChevronDownSVG = chevronDownSVG(stroke: "currentColor")

/// The Checkbox checkmark as an inline SVG data-URI (Reshaped's polyline geometry:
/// 24-unit viewBox, stroke 2, round caps). Consumed only as a *mask*, so the baked
/// stroke color is irrelevant — the glyph is filled by the pseudo-element's
/// token-driven `background-color` (the picker-icon/Dropdown-caret technique).
let swCheckmarkSVG =
    "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='white' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpolyline points='20 6 9 17 4 12'/%3E%3C/svg%3E"

/// The one stylesheet for all form controls: the column-input chrome
/// (TextField/Select), the Checkbox row, the Toggle switch (track + thumb), the
/// RadioGroup fieldset, and the shared error message. Every value reads a `--sw-*`
/// token, so the M2 media-feature layers (reduced-motion via `--sw-duration`,
/// contrast via `--sw-focus-ring`/`--sw-border-width`, dark via `light-dark()`, p3)
/// apply with no per-control code. Keep each control's selector root (`.sw-field`
/// vs `.sw-check` vs `.sw-switch` vs `.sw-radio`) disjoint so the shared blob can't
/// cross-style layouts.
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

    .sw-field__label-line {
      display: inline-flex;
      align-items: center;
      gap: var(--sw-space-xs);
    }
    .sw-field__label-prefix,
    .sw-field__label-suffix {
      display: inline-flex;
      align-items: center;
      color: var(--sw-text-muted);
      font-size: 0.8125rem;
      font-weight: normal;
    }

    /* --- Horizontal field layout (LabeledField layout: .horizontal) --- */
    /* Fixed label column so stacked fields align (the settings-form look);
       re-declare --sw-field-label-width on a scope to retune it. */
    .sw-field--h .sw-field__label {
      display: grid;
      grid-template-columns: var(--sw-field-label-width) 1fr;
      align-items: center;
      gap: var(--sw-space-sm);
    }
    /* Error aligns under the CONTROL column, not the label column. */
    .sw-field--h .sw-field-error {
      margin-inline-start: calc(var(--sw-field-label-width) + var(--sw-space-sm));
    }
    /* Autocomplete's label is for-associated (a SIBLING of the control wrap, not
       wrapping it), so horizontal lays out the ROOT as the two-column grid and
       undoes the wrapping-label grid above. The listbox popover is top-layer
       (anchor-positioned) — grid placement doesn't affect it. */
    .sw-field--h.sw-ac {
      display: grid;
      grid-template-columns: var(--sw-field-label-width) 1fr;
      align-items: center;
      column-gap: var(--sw-space-sm);
      row-gap: var(--sw-space-xs);
    }
    .sw-field--h.sw-ac .sw-field__label { display: block; }
    .sw-field--h.sw-ac .sw-field-error { grid-column: 2; margin-inline-start: 0; }

    .sw-field input,
    .sw-field select,
    .sw-field textarea {
      font: inherit;
      font-weight: normal;   /* `font: inherit` pulls weight 500 from .sw-field__label; controls aren't a label */
      width: 100%;
      box-sizing: border-box;
      padding: var(--sw-space-sm) var(--sw-space-md);   /* fallback; the size modifier overrides */
      border: var(--sw-border-width) solid var(--sw-border);
      border-radius: var(--sw-radius);
      background-color: var(--sw-surface);
      color: var(--sw-text);
      transition: border-color var(--sw-duration) var(--sw-ease),
                  box-shadow var(--sw-duration) var(--sw-ease);
    }
    .sw-field input:focus-visible,
    .sw-field select:focus-visible,
    .sw-field textarea:focus-visible {
      outline: 2px solid transparent;   /* keeps a visible focus under forced-colors */
      box-shadow: var(--sw-focus-shadow);
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
    .sw-field--xs input, .sw-field--xs select, .sw-field--xs textarea { padding: 0.125rem var(--sw-space-xs); font-size: 0.8125rem; }
    .sw-field--sm input, .sw-field--sm select, .sw-field--sm textarea { padding: var(--sw-space-xs) var(--sw-space-sm); font-size: 0.875rem; }
    .sw-field--md input, .sw-field--md select, .sw-field--md textarea { padding: var(--sw-space-sm) var(--sw-space-md); font-size: 1rem; }
    .sw-field--lg input, .sw-field--lg select, .sw-field--lg textarea { padding: var(--sw-space-md) var(--sw-space-lg); font-size: 1.125rem; }
    .sw-field textarea { resize: vertical; min-height: calc(2 * 1em + 2 * var(--sw-space-sm)); }

    /* --- Slider: custom-drawn range (Reshaped geometry, cross-browser identical) ---
       Borderless 0.25em pill track with a left-anchored accent fill, and a 1em accent
       thumb ringed by 2px of --sw-surface (Reshaped's "white border", surface-toned so
       dark mode adapts). The fill is a gradient layer sized by --sw-slider-fill, which
       Slider emits inline per render — the .value binding fires per input event, so it
       tracks the drag live. Webkit and Gecko each get their own pseudo pair. */
    .sw-field input[type="range"] {
      appearance: none;
      -webkit-appearance: none;
      padding: 0;
      border: none;
      height: 1.25em;              /* comfortable hit area; the track centers inside */
      background: none;
      cursor: pointer;
    }
    .sw-field input[type="range"]:disabled { cursor: not-allowed; }
    .sw-field input[type="range"]::-webkit-slider-runnable-track {
      height: 0.25em;
      border: none;
      border-radius: 999px;
      background: linear-gradient(var(--sw-accent), var(--sw-accent))
                  0 0 / var(--sw-slider-fill, 0%) 100% no-repeat var(--sw-border);
    }
    .sw-field input[type="range"]::-moz-range-track {
      height: 0.25em;
      border: none;
      border-radius: 999px;
      background: var(--sw-border);
    }
    .sw-field input[type="range"]::-moz-range-progress {
      height: 0.25em;
      border-radius: 999px;
      background: var(--sw-accent);
    }
    /* Knob: a 1.25em accent dot with a real 2px stroke — white in light mode,
       black in dark (explicitly light-dark, NOT --sw-surface: dark surface is
       gray and reads as no stroke). box-sizing keeps the stroke inside the
       1.25em footprint (16px dot + 2px ring @ md, Reshaped's proportions). */
    .sw-field input[type="range"]::-webkit-slider-thumb {
      appearance: none;
      -webkit-appearance: none;
      box-sizing: border-box;
      width: 1.25em;
      height: 1.25em;
      border: 2px solid light-dark(#fff, #000);
      border-radius: 50%;
      background-color: var(--sw-accent);
      margin-top: -0.5em;          /* (0.25em track − 1.25em thumb) / 2 */
      transition: box-shadow var(--sw-duration) var(--sw-ease);
    }
    .sw-field input[type="range"]::-moz-range-thumb {
      box-sizing: border-box;
      width: 1.25em;
      height: 1.25em;
      border: 2px solid light-dark(#fff, #000);
      border-radius: 50%;
      background-color: var(--sw-accent);
      transition: box-shadow var(--sw-duration) var(--sw-ease);
    }
    /* The shared .sw-field input:focus-visible ring would wrap the whole input's
       box — move it onto the thumb. */
    .sw-field input[type="range"]:focus-visible { box-shadow: none; }
    .sw-field input[type="range"]:focus-visible::-webkit-slider-thumb {
      box-shadow: var(--sw-focus-shadow);
    }
    .sw-field input[type="range"]:focus-visible::-moz-range-thumb {
      box-shadow: var(--sw-focus-shadow);
    }

    /* --- Select: skinnable native <select> --- */
    /* Fallback (all browsers): strip native chrome, draw a chevron. The base
       rules above already give border/radius/surface/padding/focus/disabled. */
    .sw-field select {
      appearance: none;
      /* Same chevron geometry as the mask path, baked at --sw-text-muted's base light/dark
         values and swapped via light-dark(). A baked SVG can't read the token, so it tracks
         base light/dark but not the prefers-contrast layer (the masked branch below does). */
      background-image: light-dark(
        url("\(chevronDownSVG(stroke: "%235b616b"))"),
        url("\(chevronDownSVG(stroke: "%239ca3af"))"));
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
      /* Replace the UA glyph: same SVG + mask technique as the Dropdown caret (here on a
         replaced-content pseudo rather than a span), so it fills with var(--sw-text-muted)
         and is dark-adaptive. content:url(svg) would bake black — currentColor doesn't
         resolve in ::picker-icon content. (Verified painting under Customizable Select.) */
      .sw-field select::picker-icon {
        content: "";
        width: 1em;
        height: 1em;
        /* Chrome's base-select UA styles make the <select> a flex container with
           align-items: normal, so this fixed-height pseudo pins to the cross-axis
           START — visually a few px above the text's center. Center it explicitly. */
        align-self: center;
        background-color: var(--sw-text-muted);
        -webkit-mask: url("\(swChevronDownSVG)") center / contain no-repeat;
        mask: url("\(swChevronDownSVG)") center / contain no-repeat;
        transition: rotate var(--sw-duration) var(--sw-ease);
      }
      .sw-field select:open::picker-icon { rotate: 180deg; }
      .sw-field ::picker(select) {
        background-color: var(--sw-surface);
        border: var(--sw-border-width) solid var(--sw-border);
        border-radius: var(--sw-radius);
        padding: var(--sw-space-xs);
        box-shadow: 0 4px 12px rgb(0 0 0 / 0.12);
      }
      /* entry/exit animation — the shared quartet (see PopoverTransition.swift):
         the option list drops 10px into place while fading in, reverses on close.
         Durations read --sw-duration, so reduced-motion makes it instant. */
      \(popoverTransitionCSS(
          base: ".sw-field ::picker(select)", open: ".sw-field select:open::picker(select)",
          closedTransform: "translateY(-10px)", openTransform: "translateY(0)"))
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

    /* --- Checkbox: custom-drawn box (Reshaped geometry) over a hidden native input --- */
    /* The native input keeps state/keyboard/AT but is sr-only-hidden (same recipe as
       .sw-switch); the .sw-check__box span is the visual. Drawn — not accent-color'd —
       so Chrome and Safari render identical pixels (native checkboxes diverge per UA).
       Box: 1.25em (20px @ md), token border, --sw-radius-sm corners; checked fills
       with the accent and scale+fades in a masked checkmark colored by
       --sw-accent-text (token-driven, dark-adaptive, accent-cascade-compatible). */
    .sw-check { display: flex; flex-direction: column; gap: var(--sw-space-xs); }
    .sw-check__row {
      position: relative;            /* containing block for the hidden input */
      display: flex;
      flex-direction: row;
      align-items: center;
      gap: var(--sw-space-sm);
      color: var(--sw-text);
      cursor: pointer;
    }
    /* The real input invisibly covers the whole row (not sr-only-clipped): clicks —
       the user's AND test tooling's — hit the input itself natively, so no
       label-forwarding is involved. (Playwright's .check() click-points the input;
       a clip-hidden 1px input gets "intercepted" by whatever paints there and
       times out. opacity: 0 keeps it hit-testable.) */
    .sw-check input {
      position: absolute;
      inset: 0;
      width: 100%;
      height: 100%;
      margin: 0;
      padding: 0;
      border: 0;
      opacity: 0;
      cursor: pointer;
    }
    .sw-check__box {
      flex: none;
      position: relative;
      /* Clicks fall through to the wrapping <label> (which activates the input
         natively). Also load-bearing for test tooling: Playwright's .check() on
         the hidden input is click-intercepted by this span unless it's
         pointer-transparent — interception by the associated label is allowed. */
      pointer-events: none;
      width: 1.25em;
      height: 1.25em;
      box-sizing: border-box;
      border: var(--sw-border-width) solid var(--sw-border);
      border-radius: var(--sw-radius-sm);
      background-color: var(--sw-surface);
      transition: background-color var(--sw-duration) var(--sw-ease),
                  border-color var(--sw-duration) var(--sw-ease),
                  box-shadow var(--sw-duration) var(--sw-ease);
    }
    .sw-check__box::after {
      content: "";
      position: absolute;
      inset: 0;
      background-color: var(--sw-accent-text);
      -webkit-mask: url("\(swCheckmarkSVG)") center / 80% no-repeat;
      mask: url("\(swCheckmarkSVG)") center / 80% no-repeat;
      opacity: 0;
      transform: scale(0.5);
      transition: opacity var(--sw-duration) var(--sw-ease),
                  transform var(--sw-duration) var(--sw-ease);
    }
    .sw-check input:checked + .sw-check__box {
      background-color: var(--sw-accent);
      border-color: var(--sw-accent);
    }
    .sw-check input:checked + .sw-check__box::after {
      opacity: 1;
      transform: scale(1);
    }
    .sw-check input:focus-visible + .sw-check__box {
      outline: 2px solid transparent;
      box-shadow: var(--sw-focus-shadow);
    }
    .sw-check input[aria-invalid="true"] + .sw-check__box {
      border-color: var(--sw-danger);
    }
    .sw-check__row--disabled {
      opacity: var(--sw-disabled-opacity);
      cursor: not-allowed;
    }
    /* Size scale: the box (1.1em) and label scale with the root font-size. */
    .sw-check--xs { font-size: 0.8125rem; }
    .sw-check--sm { font-size: 0.875rem; }
    .sw-check--md { font-size: 1rem; }
    .sw-check--lg { font-size: 1.125rem; }

    /* --- Toggle: a switch (immediate on/off setting) — track + sliding thumb --- */
    .sw-switch { display: flex; flex-direction: column; gap: var(--sw-space-xs); }
    .sw-switch__row {
      position: relative;            /* containing block for the visually-hidden input */
      display: flex;
      flex-direction: row;
      align-items: center;
      gap: var(--sw-space-sm);
      color: var(--sw-text);
      cursor: pointer;
    }
    /* The native checkbox drives state/keyboard; visually it's a full-row
       invisible overlay (see .sw-check input — same testability rationale),
       so clicks hit the input natively. The track + thumb are the visual. */
    .sw-switch input {
      position: absolute;
      inset: 0;
      width: 100%;
      height: 100%;
      margin: 0;
      padding: 0;
      border: 0;
      opacity: 0;
      cursor: pointer;
    }
    .sw-switch__track {
      flex: none;
      position: relative;
      pointer-events: none;   /* clicks fall through to the label (see .sw-check__box) */
      width: 2.25em;
      height: 1.25em;
      border-radius: 1em;
      background-color: var(--sw-border);
      transition: background-color var(--sw-duration) var(--sw-ease),
                  box-shadow var(--sw-duration) var(--sw-ease);
    }
    .sw-switch__thumb {
      position: absolute;
      top: 50%;
      inset-inline-start: 0.15em;    /* logical, so it flips for RTL */
      width: 0.95em;
      height: 0.95em;
      border-radius: 50%;
      background-color: var(--sw-surface);
      transform: translateY(-50%);
      transition: transform var(--sw-duration) var(--sw-ease);
    }
    .sw-switch input:checked + .sw-switch__track { background-color: var(--sw-accent); }
    .sw-switch input:checked + .sw-switch__track .sw-switch__thumb { transform: translate(1em, -50%); }
    [dir="rtl"] .sw-switch input:checked + .sw-switch__track .sw-switch__thumb { transform: translate(-1em, -50%); }
    .sw-switch input:focus-visible + .sw-switch__track {
      outline: 2px solid transparent;
      box-shadow: var(--sw-focus-shadow);
    }
    /* Dim the whole row when disabled (matches .sw-check), not just the track. */
    .sw-switch__row--disabled { opacity: var(--sw-disabled-opacity); cursor: not-allowed; }
    /* Size scale: the track (2.25em), thumb, and label scale with the root font-size. */
    .sw-switch--xs { font-size: 0.8125rem; }
    .sw-switch--sm { font-size: 0.875rem; }
    .sw-switch--md { font-size: 1rem; }
    .sw-switch--lg { font-size: 1.125rem; }

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
    /* Custom-drawn dot over a hidden native radio — the same Reshaped-geometry
       treatment as .sw-check__box (see the Checkbox comment above): 1.25em circle,
       checked fills with the accent and pops in a 0.5em --sw-accent-text dot. */
    .sw-radio__option {
      position: relative;            /* containing block for the hidden input */
      display: flex;
      flex-direction: row;
      align-items: center;
      gap: var(--sw-space-sm);
      color: var(--sw-text);
      cursor: pointer;
    }
    .sw-radio input {
      position: absolute;   /* full-row invisible overlay (see .sw-check input) */
      inset: 0;
      width: 100%;
      height: 100%;
      margin: 0;
      padding: 0;
      border: 0;
      opacity: 0;
      cursor: pointer;
    }
    .sw-radio__dot {
      flex: none;
      pointer-events: none;   /* clicks fall through to the label (see .sw-check__box) */
      width: 1.25em;
      height: 1.25em;
      box-sizing: border-box;
      border: var(--sw-border-width) solid var(--sw-border);
      border-radius: 50%;
      background-color: var(--sw-surface);
      /* The inner dot is a radial-gradient painted ON this element — NOT a child/
         pseudo. A separate element rasterizes in its own pass, so at fractional
         em sizes (17.5px box at sm) the browser pixel-snaps ring and dot
         independently and they drift visibly off-center (a pseudo + transform
         centering wasn't enough). One element = one raster pass = concentric by
         construction; gradients resolve var(), so the dot keeps the contrast
         token (SVG would bake the color and break the accent cascade).
         background-origin: border-box centers the dot on the same box the
         visible disk is drawn in; the 8% transparent ramp anti-aliases the edge.
         The pop animates via background-size (0 → 0.5em). */
      background-image: radial-gradient(circle closest-side,
                          var(--sw-accent-text) 92%, transparent 100%);
      background-origin: border-box;
      background-position: center;
      background-repeat: no-repeat;
      background-size: 0px 0px;
      transition: background-color var(--sw-duration) var(--sw-ease),
                  border-color var(--sw-duration) var(--sw-ease),
                  background-size var(--sw-duration) var(--sw-ease),
                  box-shadow var(--sw-duration) var(--sw-ease);
    }
    .sw-radio input:checked + .sw-radio__dot {
      background-color: var(--sw-accent);
      border-color: var(--sw-accent);
      background-size: 0.5em 0.5em;
    }
    .sw-radio input:focus-visible + .sw-radio__dot {
      outline: 2px solid transparent;
      box-shadow: var(--sw-focus-shadow);
    }
    /* The group has no single input to mark, so signal the error on the legend. */
    .sw-radio[aria-invalid="true"] .sw-radio__legend { color: var(--sw-danger); }
    .sw-radio:disabled .sw-radio__option {
      opacity: var(--sw-disabled-opacity);
      cursor: not-allowed;
    }
    /* Size scale: the dot (1.1em) and label scale with the root font-size. */
    .sw-radio--xs { font-size: 0.8125rem; }
    .sw-radio--sm { font-size: 0.875rem; }
    .sw-radio--md { font-size: 1rem; }
    .sw-radio--lg { font-size: 1.125rem; }
    """)
}
