import Testing
@testable import SwiflowUI

@Suite("Field chrome sheet — label line, adornments, horizontal layout")
@MainActor
struct FieldChromeSheetTests {
    @Test("label line + adornment spans are token-styled") func labelLine() {
        let css = formControlsSheet.cssString(scopeClass: "")
        #expect(css.contains(".sw-field__label-line"))
        #expect(css.contains(".sw-field__label-prefix"))
        #expect(css.contains(".sw-field__label-suffix"))
        #expect(css.contains("color: var(--sw-text-muted)"))
    }

    @Test("horizontal layout: root grid, fixed + hug columns, grid-placed error") func horizontal() {
        let css = formControlsSheet.cssString(scopeClass: "")
        // the ROOT is the grid; the fixed column reads the registered token
        #expect(css.contains(".sw-field--h {"))
        #expect(css.contains("grid-template-columns: var(--sw-field-label-width) 1fr"))
        // hug modifier swaps the column for max-content
        #expect(css.contains(".sw-field--h-hug { grid-template-columns: max-content 1fr; }"))
        // wrapping labels dissolve into the root grid…
        #expect(css.contains(".sw-field--h .sw-field__label { display: contents; }"))
        // …except sibling-shaped labels (Autocomplete's for-associated label, Toggle/
        // Checkbox's split-out label), which ARE the column-1 item already
        #expect(css.contains(".sw-field--h .sw-field__label--standalone { display: block; }"))
        #expect(!css.contains(".sw-ac .sw-field__label"))   // the old per-consumer coupling is gone
        // error aligns under the CONTROL column by grid placement, not width math
        #expect(css.contains(".sw-field--h .sw-field-error { grid-column: 2; }"))
        #expect(!css.contains("calc(var(--sw-field-label-width)"))
    }

    @Test("multi-node control slot stacks as one min-width-0 grid item") func controlsSlot() {
        let css = formControlsSheet.cssString(scopeClass: "")
        #expect(css.contains(".sw-field__controls"))
        #expect(css.contains("min-width: 0"))
    }
}
