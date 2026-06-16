// Sources/SwiflowUI/Autocomplete.swift
import Swiflow
#if canImport(JavaScriptKit)
import JavaScriptKit
#endif

/// A labelled **filterable combobox** (WAI-ARIA APG *combobox* pattern): a text input
/// that filters a list of `SelectOption`s as you type, in a Popover-API panel anchored
/// to the input. **Strict select-from-list** — the committed `selection` is always one
/// of the options' `.value` (or `""`); typed text that doesn't resolve to an option is
/// discarded on blur. For arbitrary free text, use `TextField`; for a fixed list with no
/// typing, use `Select`.
///
///     @State var country = ""
///     Autocomplete("Country", selection: $country,
///                  options: [SelectOption("ca", "Canada"), SelectOption("fr", "France"), "Japan"])
///
/// **Keyboard** (focus stays on the input throughout — the APG model; options are
/// non-focusable and the active one is tracked via `aria-activedescendant`): ↓ opens /
/// moves to the next option, ↑ to the previous, Enter commits the active option, Esc
/// closes. Clicking an option commits it; the trailing **✕** clears the field. Built on
/// `EventInfo.key` for the keyboard map and the Popover API + CSS anchor positioning for
/// the panel (top-layer, native light-dismiss), all token-driven.
///
/// > Notes / limits: handlers can't `preventDefault`, so ↑/↓ also nudge the input caret
/// > (benign on a single line). Anchor positioning is Chromium/Safari; Firefox falls back
/// > to a non-anchored, min-width panel. `options` are captured when the combobox is first
/// > mounted (the component is `embed`-reused) — fine for a static list; if your options
/// > change while mounted, key the embed. Async/remote suggestions + loading/empty/error
/// > states are a planned fast-follow.
@MainActor
public func Autocomplete(
    _ label: String,
    selection: Binding<String>,
    options: [SelectOption],
    placeholder: String = "",
    error: String? = nil,
    size: ControlSize = .md,
    required: Bool = false,
    disabled: Bool = false,
    filter: ((_ query: String, _ option: SelectOption) -> Bool)? = nil,
    _ attributes: Attribute...,
    onBlur: (@MainActor () -> Void)? = nil
) -> VNode {
    let caller = attributes
    return embed {
        AutocompleteBox(label: label, selection: selection, options: options,
                        placeholder: placeholder, error: error, size: size,
                        required: required, disabled: disabled, filter: filter,
                        caller: caller, onBlur: onBlur)
    }
}

/// `Field`-integrated convenience (mirrors `Select(field:)`/`TextField(field:)`):
/// wires the bound value, error + `aria-invalid`, and blur→`markTouched`.
@MainActor
public func Autocomplete(
    _ label: String,
    field: Field<String>,
    options: [SelectOption],
    placeholder: String = "",
    size: ControlSize = .md,
    required: Bool = false,
    disabled: Bool = false,
    filter: ((_ query: String, _ option: SelectOption) -> Bool)? = nil,
    _ attributes: Attribute...
) -> VNode {
    let caller = attributes
    return embed {
        AutocompleteBox(label: label, selection: field.binding, options: options,
                        placeholder: placeholder, error: field.error, size: size,
                        required: required, disabled: disabled, filter: filter,
                        caller: caller, onBlur: { field.markTouched() })
    }
}

/// The stateful implementation behind `Autocomplete`. A `@Component` because it owns the
/// transient combobox state (typed text, open/active) AND drives imperative DOM the
/// declarative tree can't express: opening/closing the Popover (`showPopover()`/
/// `hidePopover()`) and scrolling the active option into view — synced in
/// `onAppear`/`onChange`, exactly like `Alert`'s `syncOpenState`. The JS-interop bits are
/// `#if`-gated so the structure still builds + unit-tests on host.
@MainActor @Component
final class AutocompleteBox {
    private let label: String
    private let selection: Binding<String>
    private let options: [SelectOption]
    private let placeholder: String
    private let error: String?
    private let size: ControlSize
    private let required: Bool
    private let disabled: Bool
    private let filter: ((String, SelectOption) -> Bool)?
    private let caller: [Attribute]
    private let onBlur: (@MainActor () -> Void)?

    // Stable ids (init, not per-body) so ARIA wiring survives re-renders.
    private let controlID: String
    private let listID: String

    // Transient UI state — the app owns only `selection`.
    @State private var query: String = ""        // text shown while open
    @State private var open: Bool = false
    @State private var activeIndex: Int = -1      // index into `visibleOptions`; -1 = none
    @State private var typed: Bool = false        // false = browsing full list, true = filtering by `query`

    #if canImport(JavaScriptKit)
    private let inputRef = Ref<JSObject>()
    private let listRef = Ref<JSObject>()
    #endif

    init(label: String, selection: Binding<String>, options: [SelectOption], placeholder: String,
         error: String?, size: ControlSize, required: Bool, disabled: Bool,
         filter: ((String, SelectOption) -> Bool)?, caller: [Attribute],
         onBlur: (@MainActor () -> Void)?) {
        self.label = label
        self.selection = selection
        self.options = options
        self.placeholder = placeholder
        self.error = error
        self.size = size
        self.required = required
        self.disabled = disabled
        self.filter = filter
        self.caller = caller
        self.onBlur = onBlur
        let cid = nextSwID("sw-ac")
        self.controlID = cid
        self.listID = cid + "-list"
    }

    private func optionID(_ i: Int) -> String { "\(controlID)-opt-\(i)" }

    private func displayLabel(forValue v: String) -> String {
        // Fall back to the raw value (not blank) when it isn't in `options` — a committed,
        // externally-set, or persisted value should still show, never render an empty field.
        options.first(where: { $0.value == v })?.label ?? v
    }

    private func defaultMatches(_ q: String, _ opt: SelectOption) -> Bool {
        opt.label.lowercased().contains(q.lowercased())
    }

    /// The options shown in the panel: the full list while browsing (just opened, or no
    /// query), the filtered subset once the user has typed.
    private var visibleOptions: [SelectOption] {
        guard typed, !query.isEmpty else { return options }
        let match = filter ?? defaultMatches
        return options.filter { match(query, $0) }
    }

    /// The text shown in the input: the live query while open, the committed option's
    /// label while closed (so non-matching typed text is discarded on close — strict).
    private var displayValue: String {
        open ? query : displayLabel(forValue: selection.get())
    }

    // MARK: state transitions

    private func openList() {
        guard !disabled, !open else { return }
        open = true
        query = displayLabel(forValue: selection.get())   // seed so the input doesn't blank on open
        typed = false
        activeIndex = options.firstIndex(where: { $0.value == selection.get() }) ?? -1
    }

    private func closeList() {
        open = false
        activeIndex = -1
        typed = false   // displayValue now reverts to the committed label
    }

    private func commit(_ opt: SelectOption) {
        selection.set(opt.value)
        closeList()
    }

    private func onInput(_ value: String) {
        guard !disabled else { return }
        query = value
        typed = true
        open = true
        activeIndex = visibleOptions.isEmpty ? -1 : 0
    }

    private func onKeyDown(_ e: EventInfo) {
        guard !disabled else { return }
        switch e.key {
        case "ArrowDown":
            if !open { openList(); if activeIndex < 0 { activeIndex = 0 } }
            else { activeIndex = min(visibleOptions.count - 1, activeIndex + 1) }
        case "ArrowUp":
            if open, !visibleOptions.isEmpty { activeIndex = max(0, activeIndex - 1) }
        case "Enter":
            let visible = visibleOptions
            if open, activeIndex >= 0, activeIndex < visible.count { commit(visible[activeIndex]) }
        case "Escape":
            if open { closeList() }
        default:
            break
        }
    }

    private func onInputBlur() {
        closeList()
        onBlur?()
    }

    private func clear() {
        guard !disabled else { return }
        selection.set("")
        query = ""
        typed = false
        activeIndex = -1
        open = false   // clearing closes the list (consistent with blur/Escape); input keeps focus
        #if canImport(JavaScriptKit)
        _ = inputRef.wrappedValue?.focus?()   // ✕ is non-focusable, so focus never left the input
        #endif
    }

    var body: VNode {
        ensureBaseStyles()
        installFieldStyles()
        installControlSheet(id: "sw-ac", autocompleteStyleSheet)

        let visible = visibleOptions
        let committed = selection.get()
        let value = displayValue

        // --- combobox input ---
        var inputBase: [Attribute] = [
            .attr("id", controlID),
            .attr("type", "text"),
            .attr("role", "combobox"),
            .attr("aria-expanded", open ? "true" : "false"),
            .attr("aria-controls", listID),
            .attr("aria-autocomplete", "list"),
            .attr("autocomplete", "off"),
            .attr("spellcheck", "false"),
            .style("anchor-name", "--\(controlID)"),
            .property(name: "value", value: .string(value)),
            .on(.input) { (e: EventInfo) in self.onInput(e.targetValue ?? "") },
            .on(.keydown) { (e: EventInfo) in self.onKeyDown(e) },
            .on(.click) { self.openList() },
        ]
        if !placeholder.isEmpty { inputBase.append(.attr("placeholder", placeholder)) }
        if open, activeIndex >= 0, activeIndex < visible.count {
            inputBase.append(.attr("aria-activedescendant", optionID(activeIndex)))
        }
        #if canImport(JavaScriptKit)
        inputBase.append(.refBinding(AnyRefBinding(inputRef)))
        #endif
        // blur goes through the helper's seam (it owns the blur wiring); onInputBlur
        // closes+reverts, then fires the caller's onBlur (Field markTouched).
        let inputAttrs = controlInputAttributes(inputBase, error: error, required: required,
                                                disabled: disabled, onBlur: { self.onInputBlur() }, caller: caller)

        var fieldChildren: [VNode] = [element("input", attributes: inputAttrs)]
        // Clear ✕ — a NON-focusable role=button (like the options), so clicking it doesn't
        // blur the input (no focusout race); shown only when there's something to clear.
        if !disabled, !value.isEmpty {
            fieldChildren.append(element("span", attributes: [
                .class("sw-ac__clear"),
                .attr("role", "button"),
                .attr("aria-label", "Clear"),
                .on(.click) { self.clear() },
            ], children: [text("\u{00D7}")]))
        }
        let fieldWrap = element("div", attributes: [.class("sw-ac__field")], children: fieldChildren)

        // Label is `for`-associated (not wrapping) so the input's accessible name is just the
        // label text — the trailing ✕ button, a sibling of the input, doesn't pollute it.
        let labelNode = element("label", attributes: [.class("sw-field__label"), .attr("for", controlID)], children: [
            element("span", attributes: [.class("sw-field__label-text")], children: [text(label)]),
        ])

        // --- listbox popover ---
        var listChildren: [VNode] = []
        if visible.isEmpty {
            listChildren.append(element("div", attributes: [.class("sw-ac__empty")], children: [text("No results")]))
        } else {
            for (i, opt) in visible.enumerated() {
                let cls = "sw-ac__option" + (i == activeIndex ? " sw-ac__option--active" : "")
                // Options MUST stay non-focusable (no tabindex): clicking one must NOT blur
                // the input, or the blur-revert would beat this commit — that's what lets a
                // strict combobox keep focus on the input (APG) yet commit on click.
                let optAttrs: [Attribute] = [
                    .class(cls),
                    .attr("id", optionID(i)),
                    .attr("role", "option"),
                    .attr("aria-selected", opt.value == committed ? "true" : "false"),
                    .on(.click) { self.commit(opt) },
                ]
                listChildren.append(element("div", attributes: optAttrs, children: [text(opt.label)]))
            }
        }

        var listAttrs: [Attribute] = [
            .class("sw-ac__listbox"),
            .attr("id", listID),
            .attr("role", "listbox"),
            .attr("popover", "auto"),
            .style("position-anchor", "--\(controlID)"),
            .style("position-area", "bottom span-right"),
            // Native light-dismiss / Esc fires `toggle`; reconcile our `open` flag to it
            // (read the live popover state to tell a user-dismiss from our own open).
            .on(.custom("toggle")) {
                #if canImport(JavaScriptKit)
                let shown = self.listRef.wrappedValue?.matches?(":popover-open").boolean ?? false
                if !shown, self.open { self.closeList() }
                #endif
            },
        ]
        #if canImport(JavaScriptKit)
        listAttrs.append(.refBinding(AnyRefBinding(listRef)))
        #endif
        let listbox = element("div", attributes: listAttrs, children: listChildren)

        var rootChildren: [VNode] = [labelNode, fieldWrap]
        if let errorNode = fieldErrorNode(error) { rootChildren.append(errorNode) }
        rootChildren.append(listbox)
        return element("div", attributes: [.class("sw-field sw-field--\(size.modifierClass) sw-ac")],
                       children: rootChildren)
    }

    func onAppear() { syncDOM() }
    func onChange() { syncDOM() }

    /// Drive the imperative DOM from state — the popover open/close + active-option
    /// scroll. Idempotent read-diff-write: `onChange` fires after every app render (the
    /// framework walks the whole committed tree), so the `:popover-open` diff guard is
    /// what keeps this cheap. `aria-activedescendant`/`aria-expanded` are declarative
    /// (set in `body`), so only the things the tree can't express live here.
    private func syncDOM() {
        #if canImport(JavaScriptKit)
        guard let list = listRef.wrappedValue else { return }
        let shown = list.matches?(":popover-open").boolean ?? false
        if open, !shown {
            _ = list.showPopover?()
        } else if !open, shown {
            _ = list.hidePopover?()
        }
        if open, activeIndex >= 0,
           let doc = JSObject.global.document.object,
           let el = doc.getElementById?(optionID(activeIndex)).object {
            _ = el.scrollIntoView?(["block": "nearest"])
        }
        #endif
    }
}

/// Global `.sw-ac*` sheet. The panel reuses the Dropdown popover recipe (top-layer,
/// token-driven entry, `:popover-open`-only `display` so an author rule can't beat the UA
/// `display:none`-when-closed). Width tracks the input via `anchor-size()` with a
/// `min-width` fallback where anchor positioning is unsupported (Firefox).
let autocompleteStyleSheet: CSSSheet = css {
    raw("""
    .sw-ac { position: relative; }

    .sw-ac__field { position: relative; display: flex; align-items: center; }
    /* room for the trailing ✕ */
    .sw-ac__field input { padding-right: calc(var(--sw-space-md) * 2 + 1em); }

    .sw-ac__clear {
      position: absolute;
      right: var(--sw-space-sm);
      top: 50%;
      transform: translateY(-50%);
      display: inline-flex;
      align-items: center;
      justify-content: center;
      width: 1.25em;
      height: 1.25em;
      border-radius: var(--sw-radius-sm);
      color: var(--sw-text-muted);
      cursor: pointer;
      user-select: none;
      -webkit-user-select: none;
      font-size: 1.1em;
      line-height: 1;
    }
    .sw-ac__clear:hover { background-color: var(--sw-surface-2); color: var(--sw-text); }

    .sw-ac__listbox {
      margin: 0;
      inset: auto;                          /* let position-area place it; avoid UA centering */
      padding: var(--sw-space-xs);
      min-width: 12rem;
      width: anchor-size(width);            /* match the input; Firefox ignores → min-width */
      max-height: 16rem;
      overflow-y: auto;
      background-color: var(--sw-surface);
      color: var(--sw-text);
      border: var(--sw-border-width) solid var(--sw-border);
      border-radius: var(--sw-radius);
      box-shadow: var(--sw-shadow);
      margin-block: var(--sw-space-xs);
      opacity: 0;
      transform: translateY(-4px);
      transition: opacity var(--sw-duration) var(--sw-ease),
                  transform var(--sw-duration) var(--sw-ease),
                  overlay var(--sw-duration) var(--sw-ease) allow-discrete,
                  display var(--sw-duration) var(--sw-ease) allow-discrete;
    }
    /* `display` on the open state only — an author `display` in the base rule would beat
       the popover UA's `display:none`-when-closed (author wins over UA at any specificity). */
    .sw-ac__listbox:popover-open {
      display: block;
      opacity: 1;
      transform: translateY(0);
    }
    @starting-style {
      .sw-ac__listbox:popover-open { opacity: 0; transform: translateY(-4px); }
    }
    .sw-ac__listbox::backdrop { background: transparent; }   /* combobox: no dimming */

    .sw-ac__option {
      padding: var(--sw-space-sm) var(--sw-space-md);
      border-radius: var(--sw-radius-sm);
      color: var(--sw-text);
      cursor: pointer;
      user-select: none;
      -webkit-user-select: none;
    }
    .sw-ac__option:hover { background-color: var(--sw-surface-2); }
    .sw-ac__option--active { background-color: var(--sw-surface-2); }   /* keyboard highlight */
    .sw-ac__option[aria-selected="true"] { font-weight: 600; }           /* the committed option */

    .sw-ac__empty {
      padding: var(--sw-space-sm) var(--sw-space-md);
      color: var(--sw-text-muted);
    }
    """)
}
