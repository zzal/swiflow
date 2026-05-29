// Sources/App/AboutPopover+Styles.swift
import Swiflow

extension AboutPopover {
    static var scopedStyles: CSSSheet? = css {
        rule(".info-card") {
            positionAnchor("--info-anchor")
            positionArea("bottom span-right")
            // Popover top-layer reset.
            margin("0.5rem 0 0 0")
            padding("0.75rem 1rem")
            background("color-mix(in oklab, Canvas 92%, CanvasText)")
            color("CanvasText")
            border("1px solid color-mix(in oklab, CanvasText 12%, transparent)")
            borderRadius("12px")
            boxShadow("0 12px 32px -12px rgb(0 0 0 / .35)")
            maxWidth("280px")
            fontSize("0.9375rem")
        }
        rule("h3") {
            margin("0 0 0.25rem 0")
            fontSize("0.95rem")
            fontWeight("600")
        }
        rule(".body") {
            margin("0 0 0.5rem 0")
            color("color-mix(in oklab, CanvasText 80%, Canvas)")
        }
        rule("a") {
            color("color-mix(in oklab, CanvasText 70%, blue)")
            textDecoration("none")
        }
        rule("a:hover") { textDecoration("underline") }
    }
}
