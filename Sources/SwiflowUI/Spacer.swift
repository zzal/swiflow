// Sources/SwiflowUI/Spacer.swift
import Swiflow

/// A flexible gap that expands to fill free space along a flex container's main
/// axis — drop it between siblings in a `VStack`/`HStack` to push them apart.
/// Lowers to a `<div>` with `flex-grow: 1`; multiple spacers share the free
/// space equally. `minLength` sets the spacer's `flex-basis` — its size before
/// it grows — using a `--sw-space-*` token (or raw length).
///
/// Has no effect outside a flex container (a grid cell, block flow, or the
/// document root): the expansion relies entirely on `flex-grow`.
///
/// No `aria-*` is added: an empty `<div>` carries no semantics, so per the
/// native-leaning a11y baseline there's nothing to annotate.
@MainActor
public func Spacer(minLength: Spacing = .none, _ attributes: Attribute...) -> VNode {
    ensureBaseStyles()
    var styles: [Attribute] = [.style("flex-grow", "1")]
    if minLength != .none {
        styles.append(.style("flex-basis", minLength.css))
    }
    return element("div", attributes: styles + attributes)
}
