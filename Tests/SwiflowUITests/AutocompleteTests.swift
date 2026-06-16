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
    onBlur: (@MainActor () -> Void)? = nil
) -> AutocompleteBox {
    AutocompleteBox(label: "Country", selection: selection, options: options, placeholder: placeholder,
                    error: error, size: .md, required: false, disabled: disabled, filter: nil,
                    caller: [], onBlur: onBlur)
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

    @Test("clicking an option commits it and closes") func optionClickCommits() {
        HandlerAmbient.current = HandlerRegistry(); defer { HandlerAmbient.current = nil }
        let cell = Cell("")
        let box = makeBox(selection: cell.binding)
        _ = box.body
        // open, then click the 3rd option (Japan)
        firstTag(el(box.body)!, "input")!.handlers["keydown"]!.invoke(EventInfo(type: "keydown", key: "ArrowDown"))
        let japan = allWithClass(el(box.body)!, "sw-ac__option").first {
            $0.children.contains { if case .text("Japan") = $0 { return true }; return false }
        }!
        japan.handlers["click"]!.invoke(EventInfo(type: "click"))
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

    // MARK: stylesheet

    @Test("stylesheet: anchored popover listbox, token-driven, with entry animation") func stylesheet() {
        let css = autocompleteStyleSheet.cssString(scopeClass: "")
        #expect(css.contains(".sw-ac__listbox"))
        #expect(css.contains(":popover-open"))
        #expect(css.contains("@starting-style"))
        #expect(css.contains("anchor-size("))           // width tracks the input
        #expect(css.contains(".sw-ac__option"))
        #expect(css.contains("var(--sw-surface)"))
    }
}
