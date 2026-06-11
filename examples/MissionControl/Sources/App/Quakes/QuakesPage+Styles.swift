// Sources/App/Quakes/QuakesPage+Styles.swift
import Swiflow

extension QuakesPage {
    static var scopedStyles: CSSSheet? = layout + badges + animations

    static let layout = css {
        host {
            display("block")
            maxWidth("860px")
            margin("0 auto")
            padding("0 var(--sw-space-lg) var(--sw-space-xl)")
        }
        rule("h1") {
            fontSize("1.4rem")
            margin("0")
        }
        rule(".filters select") {
            padding("var(--sw-space-xs) var(--sw-space-sm)")
            borderRadius("var(--sw-radius)")
            property("font", "inherit")
        }
        rule(".feed-meta") {
            margin("0")
            color("color-mix(in srgb, var(--sw-text) 60%, transparent)")
            fontSize("0.85rem")
        }
        rule(".quake-list") {
            listStyle("none")
            margin("0")
            padding("0")
            display("flex")
            flexDirection("column")
        }
        rule(".quake-row") {
            display("grid")
            property("grid-template-columns", "5.5rem 1fr max-content")
            alignItems("center")
            gap("var(--sw-space-md)")
            padding("var(--sw-space-sm) var(--sw-space-xs)")
            borderBottom("1px solid color-mix(in srgb, var(--sw-text) 10%, transparent)")
        }
        rule(".when") {
            color("color-mix(in srgb, var(--sw-text) 60%, transparent)")
            fontSize("0.85rem")
            property("font-variant-numeric", "tabular-nums")
        }
        rule(".error") {
            color("light-dark(#b91c1c, #fca5a5)")
        }
    }

    static let badges = css {
        rule(".mag") {
            property("justify-self", "start")
            padding("2px var(--sw-space-sm)")
            borderRadius("999px")
            fontSize("0.8rem")
            fontWeight("700")
            property("font-variant-numeric", "tabular-nums")
        }
        rule(".mag-low") {
            background("color-mix(in srgb, light-dark(#16a34a, #4ade80) 18%, transparent)")
            color("light-dark(#166534, #4ade80)")
        }
        rule(".mag-mid") {
            background("color-mix(in srgb, light-dark(#d97706, #fbbf24) 18%, transparent)")
            color("light-dark(#92400e, #fbbf24)")
        }
        rule(".mag-high") {
            background("color-mix(in srgb, light-dark(#dc2626, #f87171) 22%, transparent)")
            color("light-dark(#991b1b, #f87171)")
        }
    }

    static let animations = css {
        keyframes("mc-spin") {
            to { transform("rotate(360deg)") }
        }
        rule(".live-dot") {
            display("inline-block")
            color("var(--sw-accent)")
            animation("mc-spin 1s linear infinite")
        }
    }
}
