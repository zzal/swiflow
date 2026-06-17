// Tests/SwiflowTests/CSS/ResetStyleSheetTests.swift
import Testing
import Swiflow

// Mutates the @MainActor StyleInjectionRegistry global, but every test body is
// synchronous @MainActor — bodies run atomically with no suspension points, so
// tests cannot interleave and no .serialized is needed (mirrors
// StyleInjectionRegistryTests).
@Suite("Reset stylesheet")
@MainActor
struct ResetStyleSheetTests {
    @Test("Reset is wrapped in @layer reset so unlayered app/SwiflowUI styles always win") func layered() {
        #expect(swiflowResetCSS.contains("@layer reset"))
    }

    @Test("Reset normalizes the box model on every element + pseudo-element") func boxSizing() {
        #expect(swiflowResetCSS.contains("*, *::before, *::after"))
        #expect(swiflowResetCSS.contains("box-sizing: border-box"))
    }

    @Test("Reset ships a reduced-motion floor for every app") func reducedMotion() {
        #expect(swiflowResetCSS.contains("@media (prefers-reduced-motion: reduce)"))
    }

    @Test("Reset zeroes block margins on headings, paragraphs and lists") func zeroBlockMargins() {
        #expect(swiflowResetCSS.contains("margin-block: 0"))
        // lists are covered alongside headings/paragraphs
        #expect(swiflowResetCSS.contains("ul, ol"))
    }

    @Test("Reset agrees with the scaffold template on viewport units — dvh, not svh") func viewportUnit() {
        #expect(swiflowResetCSS.contains("100dvh"))
        #expect(!swiflowResetCSS.contains("100svh"), "the templates ship 100dvh; the reset must not contradict them")
    }

    @Test("Reset does not force font-smoothing — that's taste, not normalization") func noFontSmoothing() {
        #expect(!swiflowResetCSS.contains("font-smoothing"))
    }

    @Test("installResetStyles registers the reset under id swiflow-reset exactly once") func installsOnce() {
        StyleInjectionRegistry.reset()
        var emitted: [(id: String, css: String)] = []
        StyleInjectionRegistry.emit = { id, css in emitted.append((id, css)) }
        defer {
            StyleInjectionRegistry.emit = nil
            StyleInjectionRegistry.reset()
        }

        installResetStyles()
        installResetStyles()   // idempotent — guarded by the registry

        #expect(emitted.count == 1)
        #expect(emitted.first?.id == "swiflow-reset")
        #expect(emitted.first?.css == swiflowResetCSS)
    }
}
