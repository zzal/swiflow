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
/// > change while mounted, pass a `key:` that changes with them. For **remote** suggestions, use the `loader:`
/// > overload below — async, debounced, with Searching / error / empty panel states.
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
    key: String? = nil,
    onBlur: (@MainActor () -> Void)? = nil
) -> VNode {
    let caller = attributes
    return embedKeyed(key) {
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
    _ attributes: Attribute...,
    key: String? = nil
) -> VNode {
    let caller = attributes
    return embedKeyed(key) {
        AutocompleteBox(label: label, selection: field.binding, options: options,
                        placeholder: placeholder, error: field.error, size: size,
                        required: required, disabled: disabled, filter: filter,
                        caller: caller, onBlur: { field.markTouched() })
    }
}

/// **Async / remote** combobox. Instead of filtering a static list, it calls `loader`
/// with the current query (debounced) and shows the returned `SelectOption`s — with
/// Searching / error / "No results" panel states. Everything else (strict select-from-
/// list, keyboard, clear ✕, a11y) matches the sync `Autocomplete`.
///
///     Autocomplete("City", selection: $cityID, loader: { q in try await api.cities(q) })
///
/// `loader` runs in a `.task(rerunOn: query)`: each keystroke cancels the prior run, so
/// `debounce` (seconds) is honored and stale/out-of-order responses can't overwrite fresh
/// state. A thrown error shows the error row. Below `minChars`, the panel shows a
/// "Type to search" hint and no request fires.
///
/// > A pre-set `selection` with no prior in-component commit shows the raw value until the
/// > user selects (there's no full list to look its label up in). For caching/retry, wrap
/// > the loader with SwiflowQuery.
@MainActor
public func Autocomplete(
    _ label: String,
    selection: Binding<String>,
    loader: @escaping (_ query: String) async throws -> [SelectOption],
    placeholder: String = "",
    error: String? = nil,
    size: ControlSize = .md,
    required: Bool = false,
    disabled: Bool = false,
    debounce: Double = 0.25,
    minChars: Int = 1,
    _ attributes: Attribute...,
    key: String? = nil,
    onBlur: (@MainActor () -> Void)? = nil
) -> VNode {
    let caller = attributes
    return embedKeyed(key) {
        AutocompleteBox(label: label, selection: selection, options: [],
                        placeholder: placeholder, error: error, size: size,
                        required: required, disabled: disabled, filter: nil,
                        caller: caller, onBlur: onBlur,
                        loader: loader, debounce: debounce, minChars: minChars)
    }
}

/// `Field`-integrated async convenience (mirrors the sync `Autocomplete(field:)`): wires the
/// bound value, error + `aria-invalid`, and blur→`markTouched`, with a remote `loader`.
@MainActor
public func Autocomplete(
    _ label: String,
    field: Field<String>,
    loader: @escaping (_ query: String) async throws -> [SelectOption],
    placeholder: String = "",
    size: ControlSize = .md,
    required: Bool = false,
    disabled: Bool = false,
    debounce: Double = 0.25,
    minChars: Int = 1,
    _ attributes: Attribute...,
    key: String? = nil
) -> VNode {
    let caller = attributes
    return embedKeyed(key) {
        AutocompleteBox(label: label, selection: field.binding, options: [],
                        placeholder: placeholder, error: field.error, size: size,
                        required: required, disabled: disabled, filter: nil,
                        caller: caller, onBlur: { field.markTouched() },
                        loader: loader, debounce: debounce, minChars: minChars)
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
    // Async mode: when `loader` is non-nil the panel is fed by remote results
    // (debounced) instead of filtering the static `options`.
    private let loader: ((String) async throws -> [SelectOption])?
    private let debounce: Double
    private let minChars: Int

    private var isAsync: Bool { loader != nil }

    // Stable ids (init, not per-body) so ARIA wiring survives re-renders.
    private let controlID: String
    private let listID: String

    // Transient UI state — the app owns only `selection`.
    @State private var query: String = ""        // text shown while open
    @State private var open: Bool = false
    @State private var activeIndex: Int = -1      // index into `visibleOptions`; -1 = none
    @State private var typed: Bool = false        // false = browsing full list, true = filtering by `query`
    // Async state (unused in sync mode — both default falsey, so the panel logic skips them).
    @State private var results: [SelectOption] = []   // latest loader results
    @State private var loading: Bool = false
    @State private var loadFailed: Bool = false
    // Label of the option committed THROUGH this control — so the closed input shows the
    // right label even in async mode, where the value is no longer in the current results.
    @State private var selectedOption: SelectOption? = nil

    #if canImport(JavaScriptKit)
    private let inputRef = Ref<JSObject>()
    private let listRef = Ref<JSObject>()
    #endif

    init(label: String, selection: Binding<String>, options: [SelectOption], placeholder: String,
         error: String?, size: ControlSize, required: Bool, disabled: Bool,
         filter: ((String, SelectOption) -> Bool)?, caller: [Attribute],
         onBlur: (@MainActor () -> Void)?,
         loader: ((String) async throws -> [SelectOption])? = nil,
         debounce: Double = 0.25, minChars: Int = 1) {
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
        self.loader = loader
        self.debounce = debounce
        self.minChars = minChars
        let cid = nextSwID("sw-ac")
        self.controlID = cid
        self.listID = cid + "-list"
    }

    private func optionID(_ i: Int) -> String { "\(controlID)-opt-\(i)" }

    private func displayLabel(forValue v: String) -> String {
        // Prefer the label of the option committed through this control (the only source
        // that survives async result churn), then the static options, then the raw value
        // (never blank — an externally-set/persisted value should still show).
        if let s = selectedOption, s.value == v { return s.label }
        return options.first(where: { $0.value == v })?.label ?? v
    }

    private func defaultMatches(_ q: String, _ opt: SelectOption) -> Bool {
        opt.label.lowercased().contains(q.lowercased())
    }

    /// The options shown in the panel. Async: the latest loader results (the loader does
    /// the filtering). Sync: the full list while browsing, the filtered subset once typed.
    private var visibleOptions: [SelectOption] {
        if isAsync { return results }
        guard typed, !query.isEmpty else { return options }
        let match = filter ?? defaultMatches
        return options.filter { match(query, $0) }
    }

    /// The text shown in the input: the live query once the user has typed, otherwise the
    /// committed option's label (so non-matching typed text is discarded on close — strict,
    /// and opening shows the current value rather than blanking).
    private var displayValue: String {
        (open && typed) ? query : displayLabel(forValue: selection.get())
    }

    // MARK: state transitions

    private func openList() {
        guard !disabled, !open else { return }
        open = true
        typed = false   // browsing; displayValue shows the committed label (no query seed needed)
        // Sync: pre-activate the committed option. Async: nothing loaded yet.
        activeIndex = isAsync ? -1 : (options.firstIndex(where: { $0.value == selection.get() }) ?? -1)
    }

    private func closeList() {
        open = false
        activeIndex = -1
        typed = false   // displayValue now reverts to the committed label
        query = ""       // so a fresh open+type re-filters/re-searches from scratch
        // Async: drop the transient search state — otherwise reopening flashes the previous
        // query's results, a stale error row, or (if closed mid-search) a stuck spinner.
        // `selectedOption` is KEPT — it's the committed-label memory and must survive close.
        if isAsync { results = []; loading = false; loadFailed = false }
    }

    private func commit(_ opt: SelectOption) {
        selection.set(opt.value)
        selectedOption = opt   // remember the label for the closed display (esp. async)
        closeList()
    }

    private func onInput(_ value: String) {
        guard !disabled else { return }
        query = value
        typed = true
        open = true
        // Active index is deliberately render-clamped (every consumer bounds-checks against
        // visible.count), not eagerly reconciled: async results arrive later via the .task,
        // which resets it; until then 0/-1 against the current visible set is safe.
        activeIndex = visibleOptions.isEmpty ? -1 : 0
    }

    /// Debounced remote search, driven by `.task(rerunOn: query)`. `rerunOn` cancels the
    /// in-flight run whenever `query` changes, so the sleep below is the debounce AND
    /// cancellation gives out-of-order protection: a superseded run bails before it can
    /// overwrite fresher state. Internal (not private) so host tests can drive it directly
    /// — the `.task` machinery only runs under a real mount.
    func runSearch() async {
        guard let loader else { return }
        let q = query
        guard q.count >= minChars else {
            results = []; loading = false; loadFailed = false; activeIndex = -1
            return
        }
        loading = true
        loadFailed = false
        do {
            try await Task.sleep(nanoseconds: UInt64(max(0, debounce) * 1_000_000_000))
        } catch {
            return   // cancelled by a newer keystroke → bail; the new run owns the state
        }
        do {
            let r = try await loader(q)
            guard !Task.isCancelled else { return }
            results = r
            loading = false
            activeIndex = r.isEmpty ? -1 : 0
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            loadFailed = true
            loading = false
            results = []
        }
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
        selectedOption = nil
        query = ""
        typed = false
        activeIndex = -1
        open = false   // clearing closes the list (consistent with blur/Escape); input keeps focus
        if isAsync { results = []; loading = false; loadFailed = false }
        #if canImport(JavaScriptKit)
        _ = inputRef.wrappedValue?.focus?()   // ✕ is non-focusable, so focus never left the input
        #endif
    }

    var body: VNode {
        ensureBaseStyles()
        installFieldStyles()
        installControlSheet(id: "sw-ac", autocompleteStyleSheet)

        let visible = visibleOptions
        let committedValue = selection.get()
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
        // Panel states, in priority order. The loading/error branches only fire in async
        // mode (both flags stay false in sync mode), so the sync path is unchanged.
        var listChildren: [VNode] = []
        if isAsync, query.count < minChars {
            listChildren.append(statusRow("Type to search", spinner: false))
        } else if loading {
            listChildren.append(statusRow("Searching…", spinner: true))
        } else if loadFailed {
            listChildren.append(element("div", attributes: [.class("sw-ac__error"), .attr("role", "alert")],
                                        children: [text("Couldn't load results")]))
        } else if visible.isEmpty {
            listChildren.append(element("div", attributes: [.class("sw-ac__empty")], children: [text("No results")]))
        } else {
            for (i, opt) in visible.enumerated() {
                let cls = "sw-ac__option" + (i == activeIndex ? " sw-ac__option--active" : "")
                // Commit on MOUSEDOWN, not click. A real pointer press blurs the input even
                // though options are non-focusable (WebKit/Safari do this), firing
                // onInputBlur → closeList, which hides the popover before a `click` could
                // land — so the click never commits (empty field) or a stale item sticks.
                // mousedown fires BEFORE that blur, so the commit always wins; the trailing
                // blur just re-shows the now-committed label. Options stay non-focusable so
                // focus returns to the input (APG combobox model).
                let optAttrs: [Attribute] = [
                    .class(cls),
                    .attr("id", optionID(i)),
                    .attr("role", "option"),
                    .attr("aria-selected", opt.value == committedValue ? "true" : "false"),
                    .on(.mousedown) { self.commit(opt) },
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
        let root = element("div", attributes: [.class("sw-field sw-field--\(size.modifierClass) sw-ac")],
                           children: rootChildren)
        // Async: one stable `.task` whose `rerunOn: query` cancels+restarts the debounced
        // search on every keystroke. Sync mode attaches nothing (stable .task count per
        // instance — `isAsync` is fixed at init).
        guard isAsync else { return root }
        return root.task(rerunOn: query) { await self.runSearch() }
    }

    /// A non-option status row in the panel (loading / hint), optionally with a spinner.
    private func statusRow(_ message: String, spinner: Bool) -> VNode {
        var kids: [VNode] = []
        if spinner { kids.append(Spinner(size: .sm)) }
        kids.append(element("span", attributes: [], children: [text(message)]))
        return element("div", attributes: [.class("sw-ac__status"), .attr("role", "status")], children: kids)
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
    /* async panel states: loading / "type to search" hint, and the error row */
    .sw-ac__status {
      display: flex;
      align-items: center;
      gap: var(--sw-space-sm);
      padding: var(--sw-space-sm) var(--sw-space-md);
      color: var(--sw-text-muted);
    }
    .sw-ac__error {
      padding: var(--sw-space-sm) var(--sw-space-md);
      color: var(--sw-danger-strong);
    }
    """)
}
