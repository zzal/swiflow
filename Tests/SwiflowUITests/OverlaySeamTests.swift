// Tests/SwiflowUITests/OverlaySeamTests.swift
//
// Audit V Wave-2 #4: overlay testability. DataTable models the seam
// pattern (internal cycleSort/visibleWindow); Autocomplete's state
// transitions and Dropdown's roving math were private — Autocomplete
// tests dug keydown handlers out of a re-rendered body 9×, and the pure
// roving table was untestable behind a JS-gated static. The transitions
// are now internal seams; the roving DECISION is a pure function split
// from its JS focus effect.
import Testing
@testable import Swiflow
@testable import SwiflowUI

// MARK: - Dropdown roving (pure decision table)

@Suite("DropdownMenu.roveTarget — the pure roving table")
@MainActor
struct RoveTargetTests {
    private let order = ["a", "b", "c"]

    @Test("ArrowDown advances and wraps")
    func arrowDownWraps() {
        #expect(DropdownMenu.roveTarget(key: "ArrowDown", current: "a", order: order) == .focus("b"))
        #expect(DropdownMenu.roveTarget(key: "ArrowDown", current: "c", order: order) == .focus("a"))
    }

    @Test("ArrowUp retreats and wraps")
    func arrowUpWraps() {
        #expect(DropdownMenu.roveTarget(key: "ArrowUp", current: "b", order: order) == .focus("a"))
        #expect(DropdownMenu.roveTarget(key: "ArrowUp", current: "a", order: order) == .focus("c"))
    }

    @Test("Home and End jump to the ends")
    func homeEnd() {
        #expect(DropdownMenu.roveTarget(key: "Home", current: "b", order: order) == .focus("a"))
        #expect(DropdownMenu.roveTarget(key: "End", current: "b", order: order) == .focus("c"))
    }

    @Test("Tab closes the menu — native focus progression continues")
    func tabCloses() {
        #expect(DropdownMenu.roveTarget(key: "Tab", current: "a", order: order) == .closeMenu)
    }

    @Test("unknown keys, empty order, and an unknown current id all no-op")
    func noOps() {
        #expect(DropdownMenu.roveTarget(key: "Enter", current: "a", order: order) == nil)
        #expect(DropdownMenu.roveTarget(key: nil, current: "a", order: order) == nil)
        #expect(DropdownMenu.roveTarget(key: "ArrowDown", current: "a", order: []) == nil)
        #expect(DropdownMenu.roveTarget(key: "ArrowDown", current: "zz", order: order) == nil)
    }
}

// MARK: - Autocomplete state transitions (internal seams, no handler digging)

@Suite("Autocomplete transitions through the internal seams")
@MainActor
struct AutocompleteSeamTests {
    private func box(selection: Binding<String>) -> AutocompleteBox {
        AutocompleteBox(label: "Country", selection: selection,
                        options: [SelectOption("fr", "France"), SelectOption("jp", "Japan")],
                        placeholder: "", error: nil, size: .md, required: false,
                        disabled: false, filter: nil, caller: [], onBlur: nil,
                        loader: nil, debounce: 0, minChars: 0)
    }

    @Test("openList pre-activates the committed option; closeList resets")
    func openPreactivatesCloseResets() {
        var value = "jp"
        let b = box(selection: Binding(get: { value }, set: { value = $0 }))
        b.openList()
        #expect(b.isOpenForTesting)
        #expect(b.activeIndexForTesting == 1, "the committed 'jp' is pre-activated")
        b.closeList()
        #expect(!b.isOpenForTesting)
        #expect(b.activeIndexForTesting == -1)
    }

    @Test("onKeyDown drives the whole keyboard contract without touching handlers")
    func keyboardContract() {
        var value = ""
        let b = box(selection: Binding(get: { value }, set: { value = $0 }))
        b.onKeyDown(EventInfo(type: "keydown", key: "ArrowDown"))   // opens + activates first
        #expect(b.isOpenForTesting && b.activeIndexForTesting == 0)
        b.onKeyDown(EventInfo(type: "keydown", key: "ArrowDown"))
        #expect(b.activeIndexForTesting == 1)
        b.onKeyDown(EventInfo(type: "keydown", key: "Enter"))       // commits the active option
        #expect(value == "jp")
        #expect(!b.isOpenForTesting, "commit closes")
        b.onKeyDown(EventInfo(type: "keydown", key: "ArrowDown"))
        b.onKeyDown(EventInfo(type: "keydown", key: "Escape"))
        #expect(!b.isOpenForTesting, "Escape closes without committing")
        #expect(value == "jp")
    }

    @Test("commit sets the selection, remembers the label, and closes")
    func commitContract() {
        var value = ""
        let b = box(selection: Binding(get: { value }, set: { value = $0 }))
        b.openList()
        b.commit(SelectOption("fr", "France"))
        #expect(value == "fr")
        #expect(!b.isOpenForTesting)
    }
}
