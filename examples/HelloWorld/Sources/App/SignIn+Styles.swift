// Sources/App/SignIn+Styles.swift
import Swiflow

extension SignIn {
    static var scopedStyles: CSSSheet? = css {
        rule(".signin") {
            display("flex")
            flexDirection("column")
            gap("1rem")
            maxWidth("320px")
            fontFamily("system-ui, sans-serif")
        }
        rule(".title") {
            margin("0")
            fontSize("1.25rem")
        }
        rule(".field") {
            display("flex")
            flexDirection("column")
            gap("0.25rem")
        }
        rule("input") {
            padding("0.4rem 0.6rem")
            border("1px solid color-mix(in oklab, CanvasText 18%, transparent)")
            borderRadius("6px")
            background("Canvas")
            color("CanvasText")
            fontSize("0.9375rem")
            accentColor("CanvasText")
        }
        rule("input:focus-visible") {
            property("outline", "2px solid color-mix(in oklab, CanvasText 50%, blue)")
            property("outline-offset", "2px")
        }
        rule(".error") {
            margin("0.125rem 0 0 0")
            color("oklch(.55 .2 25)")
            fontSize("0.85rem")
        }
        rule(".welcome") {
            margin("0")
            fontSize("1rem")
        }
        rule(".actions") {
            display("flex")
            gap("0.5rem")
        }
        rule("button") {
            padding("0.4rem 0.9rem")
            border("1px solid color-mix(in oklab, CanvasText 18%, transparent)")
            borderRadius("6px")
            background("color-mix(in oklab, Canvas 90%, CanvasText)")
            color("CanvasText")
            cursor("pointer")
            fontSize("0.9375rem")
        }
        rule("button:focus-visible") {
            property("outline", "2px solid color-mix(in oklab, CanvasText 50%, blue)")
            property("outline-offset", "2px")
        }
        rule(".secondary") {
            background("transparent")
        }
        rule("button[disabled]") {
            opacity("0.5")
            cursor("not-allowed")
        }
    }
}
