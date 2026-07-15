// Tests/SwiflowUITests/AutocompleteTests.swift
// Autocomplete is a filterable combobox (@Component behind the Autocomplete free fn):
// a role=combobox input + a Popover-API role=listbox of options, strict
// select-from-list. These host tests drive the real state transitions by invoking the
// rendered handlers and re-reading `.body` (@State is a plain stored var that persists
// on the instance; the open/scroll popover bits are browser-verified on the demo).
import Testing
@testable import Swiflow
@testable import SwiflowUI

@MainActor private func el(_ node: VNode?) -> ElementData? {
    if case .element(let data)? = node { return data }
    return nil
}

@MainActor private func firstTag(_ root: ElementData, _ tag: String) -> ElementData? {
    func walk(_ d: ElementData) -> ElementData? {
        if d.tag == tag { return d }
        for c in d.children { if let e = el(c), let hit = walk(e) { return hit } }
        return nil
    }
    return walk(root)
}

@MainActor private func firstWithClass(_ root: ElementData, _ cls: String) -> ElementData? {
    func walk(_ d: ElementData) -> ElementData? {
        if d.attributes["class"]?.split(separator: " ").map(String.init).contains(cls) == true { return d }
        for c in d.children { if let e = el(c), let hit = walk(e) { return hit } }
        return nil
    }
    return walk(root)
}

@MainActor private func allWithClass(_ root: ElementData, _ cls: String) -> [ElementData] {
    var out: [ElementData] = []
    func walk(_ d: ElementData) {
        if d.attributes["class"]?.split(separator: " ").map(String.init).contains(cls) == true { out.append(d) }
        for c in d.children { if let e = el(c) { walk(e) } }
    }
    walk(root); return out
}

@MainActor private final class Cell {
    var v: String
    init(_ v: String) { self.v = v }
    var binding: Binding<String> { Binding(get: { self.v }, set: { self.v = $0 }) }
}

@MainActor private func makeBox(
    selection: Binding<String>,
    options: [SelectOption] = ["Canada", "France", "Japan", "Germany"],
    placeholder: String = "Search…",
    error: String? = nil,
    disabled: Bool = false,
    layout: FieldLayout = .vertical,
    labelPrefix: VNode? = nil,
    labelSuffix: VNode? = nil,
    onBlur: (@MainActor () -> Void)? = nil
) -> AutocompleteBox {
    AutocompleteBox(label: "Country", selection: selection, options: options, placeholder: placeholder,
                    error: error, size: .md, required: false, disabled: disabled, filter: nil,
                    layout: layout, labelPrefix: labelPrefix, labelSuffix: labelSuffix,
                    caller: [], onBlur: onBlur)
}

private struct LoaderError: Error {}

@MainActor private func makeAsyncBox(
    selection: Binding<String>,
    minChars: Int = 1,
    loader: @escaping (String) async throws -> [SelectOption]
) -> AutocompleteBox {
    // debounce: 0 so tests can drive runSearch() without waiting.
    AutocompleteBox(label: "City", selection: selection, options: [], placeholder: "Search…",
                    error: nil, size: .md, required: false, disabled: false, filter: nil,
                    caller: [], onBlur: nil, loader: loader, debounce: 0, minChars: minChars)
}

/// Build a body with the handler ambient set *synchronously* for just this call. The async
/// tests `await runSearch()` between renders; the suite isn't serialized, so a sibling test
/// can null the shared `HandlerAmbient.current` while we're suspended — set it per render
/// rather than once-and-rely-across-await.
@MainActor private func render(_ box: AutocompleteBox) -> ElementData {
    let prev = HandlerAmbient.current
    HandlerAmbient.current = HandlerRegistry()
    defer { HandlerAmbient.current = prev }
    return el(box.body)!
}

@Suite("Autocomplete")
@MainActor
struct AutocompleteTests {

    // MARK: structure / a11y

    @Test("renders a role=combobox input wired to a role=listbox popover by a shared id") func comboboxRoles() {
        HandlerAmbient.current = HandlerRegistry(); defer { HandlerAmbient.current = nil }
        let root = el(makeBox(selection: Cell("").binding).body)!
        let input = firstTag(root, "input")!
        #expect(input.attributes["role"] == "combobox")
        #expect(input.attributes["aria-expanded"] == "false")
        #expect(input.attributes["aria-autocomplete"] == "list")
        #expect(input.attributes["autocomplete"] == "off")
        let list = firstWithClass(root, "sw-ac__listbox")!
        #expect(list.attributes["role"] == "listbox")
        #expect(list.attributes["popover"] == "auto")
        let listID = list.attributes["id"]!
        #expect(input.attributes["aria-controls"] == listID)
        // anchor wiring: input anchor-name matches the listbox's position-anchor
        let anchor = input.style["anchor-name"]!
        #expect(list.style["position-anchor"] == anchor)
        #expect(input.style["anchor-name"]?.hasPrefix("--sw-ac") == true)
    }

    @Test("ids are stable across re-renders (it's a @Component)") func stableID() {
        HandlerAmbient.current = HandlerRegistry(); defer { HandlerAmbient.current = nil }
        let box = makeBox(selection: Cell("").binding)
        let id1 = firstWithClass(el(box.body)!, "sw-ac__listbox")!.attributes["id"]!
        let id2 = firstWithClass(el(box.body)!, "sw-ac__listbox")!.attributes["id"]!
        #expect(id1 == id2)
    }

    @Test("all options render as role=option; the committed value is marked aria-selected") func optionsAndSelected() {
        HandlerAmbient.current = HandlerRegistry(); defer { HandlerAmbient.current = nil }
        let root = el(makeBox(selection: Cell("France").binding).body)!
        let options = allWithClass(root, "sw-ac__option")
        #expect(options.count == 4)
        #expect(options.allSatisfy { $0.attributes["role"] == "option" })
        let selected = options.filter { $0.attributes["aria-selected"] == "true" }
        #expect(selected.count == 1)
        #expect(selected.first!.children.contains { if case .text("France") = $0 { return true }; return false })
    }

    @Test("the public Autocomplete(...) free function lowers to an embedded component") func freeFunctionEmbeds() {
        HandlerAmbient.current = HandlerRegistry(); defer { HandlerAmbient.current = nil }
        let node = Autocomplete("Country", selection: Cell("").binding, options: ["A", "B"])
        if case .component = node {} else { Issue.record("expected a component node, got \(node)") }
    }

    @Test("layout adds --h to the root; adornments render in the for-associated label") func chromeParams() {
        HandlerAmbient.current = HandlerRegistry(); defer { HandlerAmbient.current = nil }
        let root = el(makeBox(selection: Cell("").binding, layout: .horizontal, labelPrefix: text("P")).body)!
        #expect(root.attributes["class"]?.contains("sw-field--h") == true)
        let label = firstTag(root, "label")!
        let line = el(label.children[0])!
        #expect(line.attributes["class"] == "sw-field__label-line")
        #expect(el(line.children[0])!.attributes["class"] == "sw-field__label-prefix")
    }

    // MARK: filtering

    @Test("typing filters the options and opens the list") func typingFilters() {
        HandlerAmbient.current = HandlerRegistry(); defer { HandlerAmbient.current = nil }
        let box = makeBox(selection: Cell("").binding)
        let input = firstTag(el(box.body)!, "input")!
        input.handlers["input"]!.invoke(EventInfo(type: "input", targetValue: "fra"))
        let root = el(box.body)!
        let options = allWithClass(root, "sw-ac__option")
        #expect(options.count == 1)   // only "France" contains "fra"
        #expect(firstTag(root, "input")!.attributes["aria-expanded"] == "true")
    }

    @Test("no matches shows the empty state, not options") func emptyState() {
        HandlerAmbient.current = HandlerRegistry(); defer { HandlerAmbient.current = nil }
        let box = makeBox(selection: Cell("").binding)
        firstTag(el(box.body)!, "input")!.handlers["input"]!.invoke(EventInfo(type: "input", targetValue: "zzz"))
        let root = el(box.body)!
        #expect(allWithClass(root, "sw-ac__option").isEmpty)
        #expect(firstWithClass(root, "sw-ac__empty") != nil)
    }

    // MARK: keyboard

    @Test("ArrowDown opens the list and activates an option") func arrowOpens() {
        HandlerAmbient.current = HandlerRegistry(); defer { HandlerAmbient.current = nil }
        let box = makeBox(selection: Cell("").binding)
        firstTag(el(box.body)!, "input")!.handlers["keydown"]!.invoke(EventInfo(type: "keydown", key: "ArrowDown"))
        let root = el(box.body)!
        let input = firstTag(root, "input")!
        #expect(input.attributes["aria-expanded"] == "true")
        let active = allWithClass(root, "sw-ac__option--active")
        #expect(active.count == 1)
        #expect(input.attributes["aria-activedescendant"] == active.first!.attributes["id"])
    }

    @Test("ArrowDown twice moves the active option down by one") func arrowMoves() {
        HandlerAmbient.current = HandlerRegistry(); defer { HandlerAmbient.current = nil }
        let box = makeBox(selection: Cell("").binding)
        let k = EventInfo(type: "keydown", key: "ArrowDown")
        firstTag(el(box.body)!, "input")!.handlers["keydown"]!.invoke(k)
        firstTag(el(box.body)!, "input")!.handlers["keydown"]!.invoke(k)
        let active = allWithClass(el(box.body)!, "sw-ac__option--active").first!
        #expect(active.children.contains { if case .text("France") = $0 { return true }; return false })  // 2nd option
    }

    @Test("Enter commits the active option and closes the list") func enterCommits() {
        HandlerAmbient.current = HandlerRegistry(); defer { HandlerAmbient.current = nil }
        let cell = Cell("")
        let box = makeBox(selection: cell.binding)
        firstTag(el(box.body)!, "input")!.handlers["keydown"]!.invoke(EventInfo(type: "keydown", key: "ArrowDown"))
        firstTag(el(box.body)!, "input")!.handlers["keydown"]!.invoke(EventInfo(type: "keydown", key: "Enter"))
        #expect(cell.v == "Canada")   // first option committed
        let input = firstTag(el(box.body)!, "input")!
        #expect(input.attributes["aria-expanded"] == "false")
        #expect(input.properties["value"] == .string("Canada"))
    }

    @Test("Escape closes the list without committing") func escapeCloses() {
        HandlerAmbient.current = HandlerRegistry(); defer { HandlerAmbient.current = nil }
        let cell = Cell("")
        let box = makeBox(selection: cell.binding)
        firstTag(el(box.body)!, "input")!.handlers["keydown"]!.invoke(EventInfo(type: "keydown", key: "ArrowDown"))
        firstTag(el(box.body)!, "input")!.handlers["keydown"]!.invoke(EventInfo(type: "keydown", key: "Escape"))
        #expect(cell.v == "")
        #expect(firstTag(el(box.body)!, "input")!.attributes["aria-expanded"] == "false")
    }

    // MARK: mouse + strictness

    @Test("selecting an option commits it on mousedown (beats the blur) and closes") func optionClickCommits() {
        HandlerAmbient.current = HandlerRegistry(); defer { HandlerAmbient.current = nil }
        let cell = Cell("")
        let box = makeBox(selection: cell.binding)
        _ = box.body
        // open, then select Japan via mousedown (the real-pointer commit event)
        firstTag(el(box.body)!, "input")!.handlers["keydown"]!.invoke(EventInfo(type: "keydown", key: "ArrowDown"))
        let japan = allWithClass(el(box.body)!, "sw-ac__option").first {
            $0.children.contains { if case .text("Japan") = $0 { return true }; return false }
        }!
        #expect(japan.handlers["click"] == nil)   // NOT click — that loses the blur race in WebKit
        japan.handlers["mousedown"]!.invoke(EventInfo(type: "mousedown"))
        #expect(cell.v == "Japan")
        #expect(firstTag(el(box.body)!, "input")!.attributes["aria-expanded"] == "false")
    }

    @Test("strict: non-matching typed text reverts to the committed value on blur") func strictRevertOnBlur() {
        HandlerAmbient.current = HandlerRegistry(); defer { HandlerAmbient.current = nil }
        let cell = Cell("")
        let box = makeBox(selection: cell.binding)
        let input = firstTag(el(box.body)!, "input")!
        input.handlers["input"]!.invoke(EventInfo(type: "input", targetValue: "xyz"))
        #expect(firstTag(el(box.body)!, "input")!.properties["value"] == .string("xyz"))   // shown while open
        firstTag(el(box.body)!, "input")!.handlers["blur"]!.invoke(EventInfo(type: "blur"))
        #expect(firstTag(el(box.body)!, "input")!.properties["value"] == .string(""))       // discarded → committed ("")
        #expect(cell.v == "")
    }

    // MARK: clear button

    @Test("the clear ✕ shows when there's a value and clears the selection on click") func clearButton() {
        HandlerAmbient.current = HandlerRegistry(); defer { HandlerAmbient.current = nil }
        let cell = Cell("France")
        let box = makeBox(selection: cell.binding)
        let clear = firstWithClass(el(box.body)!, "sw-ac__clear")!
        #expect(clear.attributes["role"] == "button")
        #expect(clear.attributes["aria-label"] == "Clear")
        clear.handlers["click"]!.invoke(EventInfo(type: "click"))
        #expect(cell.v == "")
        #expect(firstWithClass(el(box.body)!, "sw-ac__clear") == nil)   // gone once empty
    }

    @Test("the clear ✕ is absent when there's nothing to clear") func clearAbsentWhenEmpty() {
        HandlerAmbient.current = HandlerRegistry(); defer { HandlerAmbient.current = nil }
        #expect(firstWithClass(el(makeBox(selection: Cell("").binding).body)!, "sw-ac__clear") == nil)
    }

    @Test("clearing ✕ while the list is open closes it (consistent with blur/Escape)") func clearWhileOpenCloses() {
        HandlerAmbient.current = HandlerRegistry(); defer { HandlerAmbient.current = nil }
        let cell = Cell("")
        let box = makeBox(selection: cell.binding)
        firstTag(el(box.body)!, "input")!.handlers["input"]!.invoke(EventInfo(type: "input", targetValue: "fr"))
        #expect(firstTag(el(box.body)!, "input")!.attributes["aria-expanded"] == "true")
        firstWithClass(el(box.body)!, "sw-ac__clear")!.handlers["click"]!.invoke(EventInfo(type: "click"))
        #expect(cell.v == "")
        #expect(firstTag(el(box.body)!, "input")!.attributes["aria-expanded"] == "false")
    }

    // MARK: opening a committed value (seed + full list) / out-of-list value

    @Test("opening a committed combobox shows its label and the full list, then filters on type") func openFromCommitted() {
        HandlerAmbient.current = HandlerRegistry(); defer { HandlerAmbient.current = nil }
        let box = makeBox(selection: Cell("France").binding)
        firstTag(el(box.body)!, "input")!.handlers["keydown"]!.invoke(EventInfo(type: "keydown", key: "ArrowDown"))
        let root = el(box.body)!
        #expect(firstTag(root, "input")!.properties["value"] == .string("France"))   // seeded
        #expect(allWithClass(root, "sw-ac__option").count == 4)                       // full list while browsing
        firstTag(root, "input")!.handlers["input"]!.invoke(EventInfo(type: "input", targetValue: "fra"))
        #expect(allWithClass(el(box.body)!, "sw-ac__option").count == 1)              // filters on type
    }

    @Test("a committed value not in the options still shows (raw), not blank") func committedNotInOptions() {
        HandlerAmbient.current = HandlerRegistry(); defer { HandlerAmbient.current = nil }
        let root = el(makeBox(selection: Cell("Atlantis").binding).body)!
        #expect(firstTag(root, "input")!.properties["value"] == .string("Atlantis"))
        #expect(firstWithClass(root, "sw-ac__clear") != nil)   // non-empty value → ✕ shows
    }

    // MARK: disabled / error / field

    @Test("disabled marks the input disabled and hides the clear ✕") func disabled() {
        HandlerAmbient.current = HandlerRegistry(); defer { HandlerAmbient.current = nil }
        let root = el(makeBox(selection: Cell("France").binding, disabled: true).body)!
        #expect(firstTag(root, "input")!.attributes["disabled"] == "")
        #expect(firstWithClass(root, "sw-ac__clear") == nil)
    }

    @Test("an error renders the shared role=alert message and aria-invalid") func errorAlert() {
        HandlerAmbient.current = HandlerRegistry(); defer { HandlerAmbient.current = nil }
        let root = el(makeBox(selection: Cell("").binding, error: "Required").body)!
        let err = firstWithClass(root, "sw-field-error")!
        #expect(err.attributes["role"] == "alert")
        #expect(firstTag(root, "input")!.attributes["aria-invalid"] == "true")
    }

    @Test("blur fires the onBlur callback (Field markTouched wiring)") func blurFiresOnBlur() {
        HandlerAmbient.current = HandlerRegistry(); defer { HandlerAmbient.current = nil }
        var blurred = false
        let box = makeBox(selection: Cell("").binding, onBlur: { blurred = true })
        firstTag(el(box.body)!, "input")!.handlers["blur"]!.invoke(EventInfo(type: "blur"))
        #expect(blurred)
    }

    // MARK: async / remote loader  (use render(_:) — these await, so the ambient is set per build)

    @Test("the async Autocomplete(loader:) free function lowers to an embedded component") func asyncEmbeds() {
        let node = Autocomplete("City", selection: Cell("").binding, loader: { _ in [] })
        if case .component = node {} else { Issue.record("expected a component node, got \(node)") }
    }

    @Test("async shows a 'type to search' hint below minChars, no options") func asyncHintBelowMinChars() {
        let root = render(makeAsyncBox(selection: Cell("").binding, minChars: 2) { _ in [] })
        #expect(firstWithClass(root, "sw-ac__status") != nil)        // hint row
        #expect(allWithClass(root, "sw-ac__option").isEmpty)
        #expect(firstWithClass(root, "sw-ac__empty") == nil)         // not "No results" — we haven't searched
    }

    @Test("async loader populates the panel with its results") func asyncResults() async {
        let box = makeAsyncBox(selection: Cell("").binding) { q in
            [SelectOption("ca", "Canada"), SelectOption("fr", "France")]
                .filter { $0.label.lowercased().contains(q.lowercased()) }
        }
        firstTag(render(box), "input")!.handlers["input"]!.invoke(EventInfo(type: "input", targetValue: "can"))
        await box.runSearch()
        let opts = allWithClass(render(box), "sw-ac__option")
        #expect(opts.count == 1)
        #expect(opts.first!.children.contains { if case .text("Canada") = $0 { return true }; return false })
    }

    @Test("async loader empty result shows 'No results' (not the hint)") func asyncEmptyResults() async {
        let box = makeAsyncBox(selection: Cell("").binding) { _ in [] }
        firstTag(render(box), "input")!.handlers["input"]!.invoke(EventInfo(type: "input", targetValue: "zzz"))
        await box.runSearch()
        let root = render(box)
        #expect(firstWithClass(root, "sw-ac__empty") != nil)
        #expect(firstWithClass(root, "sw-ac__status") == nil)
    }

    @Test("async loader error shows the error row") func asyncError() async {
        let box = makeAsyncBox(selection: Cell("").binding) { _ in throw LoaderError() }
        firstTag(render(box), "input")!.handlers["input"]!.invoke(EventInfo(type: "input", targetValue: "x"))
        await box.runSearch()
        let root = render(box)
        #expect(firstWithClass(root, "sw-ac__error")?.attributes["role"] == "alert")
        #expect(allWithClass(root, "sw-ac__option").isEmpty)
    }

    @Test("async: a committed option's label persists when closed, even after results change") func asyncCommittedLabel() async {
        let cell = Cell("")
        let box = makeAsyncBox(selection: cell.binding) { q in
            q.lowercased().contains("ca") ? [SelectOption("ca", "Canada")] : []
        }
        firstTag(render(box), "input")!.handlers["input"]!.invoke(EventInfo(type: "input", targetValue: "ca"))
        await box.runSearch()
        allWithClass(render(box), "sw-ac__option").first!.handlers["mousedown"]!.invoke(EventInfo(type: "mousedown"))
        #expect(cell.v == "ca")
        // closed; the current results no longer contain "ca", but the input shows the label
        #expect(firstTag(render(box), "input")!.properties["value"] == .string("Canada"))
    }

    @Test("async: closing clears the panel (no stale results / stuck spinner on reopen)") func asyncCloseResets() async {
        let box = makeAsyncBox(selection: Cell("").binding) { q in
            q.lowercased().contains("ca") ? [SelectOption("ca", "Canada")] : []
        }
        firstTag(render(box), "input")!.handlers["input"]!.invoke(EventInfo(type: "input", targetValue: "ca"))
        await box.runSearch()
        #expect(allWithClass(render(box), "sw-ac__option").count == 1)   // results present before close
        firstTag(render(box), "input")!.handlers["blur"]!.invoke(EventInfo(type: "blur"))
        let root = render(box)
        #expect(allWithClass(root, "sw-ac__option").isEmpty)   // results dropped on close
        #expect(firstWithClass(root, "sw-spinner") == nil)      // not stuck on "Searching…"
    }

    // MARK: stylesheet

    @Test("stylesheet: anchored popover listbox, token-driven, with entry animation") func stylesheet() {
        let css = autocompleteStyleSheet.cssString(scopeClass: "")
        #expect(css.contains(".sw-ac__listbox"))
        #expect(css.contains(":popover-open"))
        #expect(css.contains("@starting-style"))
        #expect(css.contains("anchor-size("))           // width tracks the input
        #expect(css.contains(".sw-ac__option"))
        #expect(css.contains("var(--sw-surface)"))
        #expect(css.contains(".sw-ac__status"))   // async loading/hint row
        #expect(css.contains(".sw-ac__error"))     // async error row
    }
}
