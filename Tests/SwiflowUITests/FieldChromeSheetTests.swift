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

    @Test("horizontal layout: fixed label column via the registered token") func horizontal() {
        let css = formControlsSheet.cssString(scopeClass: "")
        #expect(css.contains(".sw-field--h .sw-field__label"))
        #expect(css.contains("grid-template-columns: var(--sw-field-label-width) 1fr"))
        // error aligns under the CONTROL column
        #expect(css.contains(".sw-field--h .sw-field-error"))
        #expect(css.contains("calc(var(--sw-field-label-width) + var(--sw-space-sm))"))
        // Autocomplete override (its label doesn't wrap the control)
        #expect(css.contains(".sw-field--h.sw-ac"))
    }
}
