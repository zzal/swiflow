// Sources/App/Weather/CityCard+Styles.swift
import Swiflow

extension CityCard {
    // The card surface (bg / shadow / radius / padding) now comes from SwiflowUI's
    // `Card`; only the content typography is styled here.
    static var scopedStyles: CSSSheet? = css {
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
        rule(".error") {
            color("light-dark(#b91c1c, #fca5a5)")
            margin("0")
        }
    }
}
