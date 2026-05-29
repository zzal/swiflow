// Sources/App/Toast+Styles.swift
import Swiflow

extension Toast {
    static var scopedStyles: CSSSheet? = layout + theme + animations

    static let layout = css {
        host {
            position("fixed")
            insetBlockEnd("1.5rem")
            insetInline("0")
            marginInline("auto")
            width("max-content")
            maxWidth("min(90vw, 360px)")
            display("flex")
            alignItems("center")
            gap("0.625rem")
            padding("0.75rem 1rem")
            // Popover top-layer rendering resets these — set them explicitly.
            margin("auto auto 1.5rem auto")
            inset("auto 0 0 0")
            border("0")
        }
        rule(".icon") {
            display("grid")
            placeItems("center")
            width("1.25rem")
            height("1.25rem")
            borderRadius("50%")
            fontSize("0.8rem")
        }
    }

    static let theme = css {
        host {
            background("color-mix(in oklab, Canvas 88%, CanvasText)")
            color("CanvasText")
            borderRadius("999px")
            border("1px solid color-mix(in oklab, CanvasText 12%, transparent)")
            boxShadow("0 12px 32px -12px rgb(0 0 0 / .35), 0 2px 6px -2px rgb(0 0 0 / .15)")
            fontSize("0.9375rem")
        }
        rule(".icon") {
            background("color-mix(in oklab, currentColor 18%, transparent)")
        }
    }

    static let animations = css {
        keyframes("toast-in") {
            from { opacity("0"); transform("translateY(12px) scale(.96)") }
            to   { opacity("1"); transform("translateY(0) scale(1)") }
        }
        keyframes("toast-out") {
            to { opacity("0"); transform("translateY(12px) scale(.98)") }
        }
        host {
            animation("toast-in .22s cubic-bezier(.2,.7,.2,1) forwards")
        }
    }
}
