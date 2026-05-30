// Sources/App/EdgeLab+Styles.swift
import Swiflow

extension EdgeLab {
    static var scopedStyles: CSSSheet? = css {
        host { display("block"); maxWidth("760px"); margin("1.5rem auto"); padding("0 1rem") }
        rule("section") {
            border("1px solid color-mix(in oklab, CanvasText 15%, transparent)")
            borderRadius("8px"); padding("0.75rem 1rem"); margin("0 0 1rem 0")
        }
        rule("h2") { fontSize("1rem"); margin("0 0 0.5rem 0") }
        rule("button") {
            margin("0 0.35rem 0.35rem 0"); padding("0.3rem 0.7rem")
            border("1px solid color-mix(in oklab, CanvasText 25%, transparent)")
            borderRadius("6px"); background("Canvas"); color("CanvasText"); cursor("pointer")
        }
        rule("input") {
            padding("0.25rem 0.5rem"); border("1px solid color-mix(in oklab, CanvasText 25%, transparent)")
            borderRadius("6px"); background("Canvas"); color("CanvasText")
        }
        rule(".row") { display("flex"); gap("0.4rem"); alignItems("center"); flexWrap("wrap") }
        rule(".tag") { fontFamily("ui-monospace, monospace"); fontSize("0.8rem"); color("var(--text-dim, GrayText)") }
    }
}
