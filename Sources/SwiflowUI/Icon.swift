// Sources/SwiflowUI/Icon.swift
//
// A stateless, single-color SVG seam. The js-driver builds every DOM node via
// `document.createElement` (js-driver/swiflow-driver.js:139) — no SVG namespace —
// so an `element("svg")` VNode would produce a dead `HTMLUnknownElement`, not a
// rendered vector. Icon instead reuses the codebase's own icon precedent: a
// `<span>` sized in `em`s, filled with `background-color: currentColor`, and
// clipped to the caller's SVG shape via CSS `mask`/`-webkit-mask` (the same
// technique as `.sw-dropdown__caret` in Dropdown.swift and Select's
// `::picker-icon` in FieldChrome.swift). Because the mask only carries alpha,
// the rendered icon is always exactly the current text color — single-color
// art only. Tint it with `.style("color", Token.accent.css)` or by nesting it
// under a colored parent; multi-color art (a two-tone logo, a colored
// illustration) can't be masked meaningfully and should use `rawHTML` instead
// (trusted, unescaped markup — see `Sources/Swiflow/DSL/RawHTML.swift`).
import Swiflow

/// `Icon`'s size, in `em`s so it tracks the surrounding text: `.sm` 0.875em,
/// `.md` (default) 1em, `.lg` 1.5em. Maps to a `sw-icon--<variant>` class
/// (`Text`/`Container`'s shape).
public enum IconSize: Equatable {
    case sm, md, lg
    var modifierClass: String {
        switch self {
        case .sm: return "sm"
        case .md: return "md"
        case .lg: return "lg"
        }
    }
}

/// Percent-encodes a trusted `<svg>…</svg>` string into a `url("data:image/svg+xml,…")`
/// value suitable for CSS `mask`/`-webkit-mask`. Internal — also the seam
/// `IconTests` uses to assert the encoding directly.
///
/// Encoding order matters: a literal `%` in the input is escaped to `%25`
/// FIRST, before any other substitution introduces new `%` sequences of its
/// own (`<` → `%3C` etc.) — encoding `%` last would re-escape those and
/// corrupt the URI. After that: `"` → `'` (a replacement, not a percent
/// escape — data URIs read more cleanly with single-quoted SVG attributes,
/// matching `chevronDownSVG` at FieldChrome.swift:119), then the handful of
/// characters that are reserved inside a URI component: `<` → `%3C`,
/// `>` → `%3E`, `#` → `%23` (an unescaped `#` would truncate the data URI at
/// what CSS reads as a fragment).
func svgMaskURI(_ svg: String) -> String {
    let trimmed = trimmedWhitespace(svg)
    let percentEscaped = trimmed.replacing("%", with: "%25")
    let quoted = percentEscaped.replacing("\"", with: "'")
    let encoded = quoted
        .replacing("<", with: "%3C")
        .replacing(">", with: "%3E")
        .replacing("#", with: "%23")
    return "url(\"data:image/svg+xml,\(encoded)\")"
}

/// Foundation-free whitespace trim (SwiflowUI avoids importing Foundation just
/// for `trimmingCharacters(in:)` — see the note on `Column.swift`'s
/// `ComparisonResult` avoidance for the same discipline).
private func trimmedWhitespace(_ s: String) -> String {
    var sub = Substring(s)
    while let first = sub.first, first.isWhitespace { sub.removeFirst() }
    while let last = sub.last, last.isWhitespace { sub.removeLast() }
    return String(sub)
}

/// A stateless, single-color icon: a `<span>` masked to the caller's inline
/// `svg` markup (see the file-level doc comment for the WHY behind the mask
/// approach). Apps bring their own icons — `svg` is trusted, hand-authored
/// (or hand-copied) markup, not user input.
///
/// `label: nil` (the default) renders the icon as purely decorative
/// (`aria-hidden="true"`, no role) — appropriate when adjacent visible text
/// already conveys the meaning (e.g. a checkmark beside "Saved"). Pass
/// `label:` when the icon is the ONLY conveyor of meaning (an icon-only
/// button) — it then renders `role="img"` + `aria-label`, with no
/// `aria-hidden`.
///
/// Single-color only: the mask takes on whatever `currentColor` resolves to,
/// so multi-color art (e.g. a two-tone logo) will render as a flat silhouette.
/// Tint an `Icon` with `.style("color", Token.accent.css)`, or nest it under a
/// colored parent; for genuinely multi-color art, render the SVG directly via
/// `rawHTML(_:)` instead (`Sources/Swiflow/DSL/RawHTML.swift`) — that escape
/// hatch bypasses the mask (and the DOM-namespace limitation) entirely by
/// injecting real markup via `innerHTML`.
///
///     Icon(checkSVG)                                        // decorative, md, currentColor
///     Icon(gearSVG, size: .lg)
///     Icon(checkSVG, .style("color", Token.accent.css))     // tinted
///     Icon(closeSVG, label: "Close")                        // icon-only control's accessible name
@MainActor
public func Icon(
    _ svg: String,
    size: IconSize = .md,
    label: String? = nil,
    _ attributes: Attribute...
) -> VNode {
    ensureBaseStyles()
    installControlSheet(id: "sw-icon", iconStyleSheet)

    let trimmed = trimmedWhitespace(svg)
    #if DEBUG
    if !trimmed.hasPrefix("<svg") {
        swiflowDiagnostic("Icon: the `svg` argument doesn't start with `<svg` (after trimming whitespace) — pass the full `<svg>…</svg>` markup, not a data URI or a fragment. Rendering without a mask.")
    }
    #endif

    let (callerClasses, callerRest) = splitClasses(attributes)
    let classValue = (["sw-icon", "sw-icon--\(size.modifierClass)"] + callerClasses).joined(separator: " ")

    var attrs: [Attribute] = [.class(classValue)]
    if let label {
        attrs.append(.attr("role", "img"))
        attrs.append(.attr("aria-label", label))
    } else {
        attrs.append(.attr("aria-hidden", "true"))
    }

    if trimmed.hasPrefix("<svg") {
        let maskValue = svgMaskURI(svg) + " center / contain no-repeat"
        attrs.append(.style("-webkit-mask", maskValue))
        attrs.append(.style("mask", maskValue))
    }
    attrs += callerRest

    return element("span", attributes: attrs, children: [])
}

let iconStyleSheet: CSSSheet = css {
    raw("""
    .sw-icon { display: inline-block; flex: none; background-color: currentColor; vertical-align: -0.125em; }
    .sw-icon--sm { width: 0.875em; height: 0.875em; }
    .sw-icon--md { width: 1em; height: 1em; }
    .sw-icon--lg { width: 1.5em; height: 1.5em; }
    """)
}
