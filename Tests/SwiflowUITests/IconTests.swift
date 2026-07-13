// Tests/SwiflowUITests/IconTests.swift
import Testing
import Swiflow
@testable import SwiflowUI

@MainActor
private func elementOf(_ node: VNode) -> ElementData? {
    guard case .element(let data) = node else { return nil }
    return data
}

/// Capture `swiflowDiagnostic` messages instead of trapping the process — same
/// seam as `FieldChromeDiagnosticTests`/`QueryDiagnosticsTests` (the override
/// is public, so a plain `import Swiflow` is enough — no `@testable` needed
/// just for this).
private func capturingDiagnostics(_ body: () -> Void) -> [String] {
    var captured: [String] = []
    let prior = _swiflowDiagnosticOverride
    _swiflowDiagnosticOverride = { captured.append($0) }
    defer { _swiflowDiagnosticOverride = prior }
    body()
    return captured
}

private let checkSVG = "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16'><path d='M3 8l4 4 6-8'/></svg>"

@Suite("Icon")
@MainActor
struct IconTests {
    @Test("renders <span class=\"sw-icon sw-icon--md\"> with a percent-encoded mask") func rendersDefault() {
        let el = elementOf(Icon(checkSVG))!
        #expect(el.tag == "span")
        #expect(el.attributes["class"] == "sw-icon sw-icon--md")
        let mask = el.style["mask"] ?? ""
        #expect(mask.contains("%3Csvg"))
        #expect(!mask.contains("<svg"))
        #expect(el.style["-webkit-mask"] == mask)
    }

    @Test("size: .sm maps to sw-icon--sm") func smSize() {
        let el = elementOf(Icon(checkSVG, size: .sm))!
        #expect(el.attributes["class"] == "sw-icon sw-icon--sm")
    }

    @Test("size: .md maps to sw-icon--md") func mdSize() {
        let el = elementOf(Icon(checkSVG, size: .md))!
        #expect(el.attributes["class"] == "sw-icon sw-icon--md")
    }

    @Test("size: .lg maps to sw-icon--lg") func lgSize() {
        let el = elementOf(Icon(checkSVG, size: .lg))!
        #expect(el.attributes["class"] == "sw-icon sw-icon--lg")
    }

    @Test("label: nil (the default) is decorative: aria-hidden=\"true\", no role") func decorativeByDefault() {
        let el = elementOf(Icon(checkSVG))!
        #expect(el.attributes["aria-hidden"] == "true")
        #expect(el.attributes["role"] == nil)
        #expect(el.attributes["aria-label"] == nil)
    }

    @Test("label: \"Close\" is meaningful: role=\"img\" + aria-label, no aria-hidden") func labeledIsMeaningful() {
        let el = elementOf(Icon(checkSVG, label: "Close"))!
        #expect(el.attributes["role"] == "img")
        #expect(el.attributes["aria-label"] == "Close")
        #expect(el.attributes["aria-hidden"] == nil)
    }

    @Test("caller class merges with sw-icon instead of clobbering it") func callerClassMerges() {
        let el = elementOf(Icon(checkSVG, .class("mine")))!
        #expect(el.attributes["class"] == "sw-icon sw-icon--md mine")
    }

    @Test("caller attributes merge onto the element") func callerAttributesMerge() {
        let el = elementOf(Icon(checkSVG, .attr("data-testid", "check-icon")))!
        #expect(el.attributes["data-testid"] == "check-icon")
    }

    @Test("a non-<svg string fires a DEBUG diagnostic") func nonSVGFiresDiagnostic() {
        let msgs = capturingDiagnostics {
            _ = Icon("<div>not an svg</div>")
        }
        #expect(msgs.contains { $0.contains("<svg") })
    }

    @Test("a well-formed <svg> string does not fire a diagnostic") func wellFormedSVGIsClean() {
        let msgs = capturingDiagnostics {
            _ = Icon(checkSVG)
        }
        #expect(msgs.isEmpty)
    }

    // MARK: - svgMaskURI

    @Test("svgMaskURI encodes % first, then \" → ', then <, >, #") func encodesFixtureInOrder() {
        let fixture = #"<svg data-note="50% off #1">"#
        let result = svgMaskURI(fixture)
        #expect(result == "url(\"data:image/svg+xml,%3Csvg data-note='50%25 off %231'%3E\")")
    }

    @Test("svgMaskURI trims surrounding whitespace before encoding") func trimsWhitespace() {
        let result = svgMaskURI("  <svg></svg>\n")
        #expect(result == "url(\"data:image/svg+xml,%3Csvg%3E%3C/svg%3E\")")
    }

    @Test("svgMaskURI round-trips the chevron's own hand-encoded output") func chevronRoundTrips() {
        let chevronRaw = "<svg xmlns='http://www.w3.org/2000/svg' width='16' height='16' viewBox='0 0 16 16' "
            + "fill='none' stroke='currentColor' stroke-width='1.75' stroke-linecap='round' "
            + "stroke-linejoin='round'><path d='M4 6l4 4 4-4'/></svg>"
        #expect(svgMaskURI(chevronRaw) == "url(\"\(swChevronDownSVG)\")")
    }
}
