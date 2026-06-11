// Sources/App/Weather/CityCard+Styles.swift
import Swiflow

extension CityCard {
    static var scopedStyles: CSSSheet? = css {
        host {
            display("block")
            property("min-width", "200px")
            padding("var(--sw-space-md) var(--sw-space-lg)")
            borderRadius("calc(var(--sw-radius) * 1.5)")
            background("var(--sw-surface)")
            border("1px solid color-mix(in srgb, var(--sw-text) 12%, transparent)")
            boxShadow("0 16px 32px -24px rgb(0 0 0 / .35)")
        }
        rule(".city-name") {
            fontSize("1.05rem")
            margin("0")
        }
        rule(".temp") {
            fontSize("2.2rem")
            fontWeight("700")
            lineHeight("1")
        }
        rule(".wmo") {
            fontSize("1.6rem")
        }
        rule(".wmo-label, .range") {
            margin("0")
            color("color-mix(in srgb, var(--sw-text) 60%, transparent)")
            fontSize("0.85rem")
        }
        rule(".unpin") {
            border("none")
            background("transparent")
            color("color-mix(in srgb, var(--sw-text) 50%, transparent)")
            cursor("pointer")
            fontSize("0.9rem")
            padding("0 var(--sw-space-xs)")
        }
        rule(".unpin:hover") {
            color("light-dark(#b91c1c, #fca5a5)")
        }
        rule(".live-dot") {
            color("var(--sw-accent)")
            fontSize("0.9rem")
        }
        rule(".error") {
            color("light-dark(#b91c1c, #fca5a5)")
            margin("0")
        }
    }
}
