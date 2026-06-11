// Sources/App/Weather/WeatherPage+Styles.swift
import Swiflow

extension WeatherPage {
    static var scopedStyles: CSSSheet? = layout + theme

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
        rule(".search-box input") {
            width("100%")
            property("box-sizing", "border-box")
            padding("var(--sw-space-sm) var(--sw-space-md)")
            borderRadius("var(--sw-radius)")
            fontSize("1rem")
        }
        rule(".search-results") {
            listStyle("none")
            margin("0")
            padding("var(--sw-space-xs)")
            display("flex")
            flexDirection("column")
            gap("var(--sw-space-xs)")
        }
        rule(".search-hit") {
            width("100%")
            textAlign("left")
            padding("var(--sw-space-xs) var(--sw-space-md)")
            borderRadius("var(--sw-radius)")
            cursor("pointer")
        }
    }

    static let theme = css {
        rule(".search-box input") {
            border("1px solid color-mix(in srgb, var(--sw-text) 20%, transparent)")
            background("var(--sw-surface)")
            color("var(--sw-text)")
        }
        rule(".search-results") {
            background("var(--sw-surface)")
            border("1px solid color-mix(in srgb, var(--sw-text) 15%, transparent)")
            borderRadius("var(--sw-radius)")
        }
        rule(".search-hit") {
            border("none")
            background("transparent")
            color("var(--sw-text)")
            property("font", "inherit")
        }
        rule(".search-hit:hover") {
            background("color-mix(in srgb, var(--sw-accent) 15%, transparent)")
        }
        rule(".search-status") {
            color("color-mix(in srgb, var(--sw-text) 60%, transparent)")
            margin("0")
        }
        rule(".error") {
            color("light-dark(#b91c1c, #fca5a5)")
            margin("0")
        }
        rule(".unit-select") {
            padding("var(--sw-space-xs) var(--sw-space-sm)")
            borderRadius("var(--sw-radius)")
            property("font", "inherit")
        }
    }
}
