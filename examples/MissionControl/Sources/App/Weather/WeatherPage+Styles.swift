// Sources/App/Weather/WeatherPage+Styles.swift
import Swiflow

extension WeatherPage {
    @MainActor static var scopedStyles: CSSSheet? = layout + theme

    static let layout = css {
        host(.display("block"),
             .maxWidth("860px"),
             .margin("0 auto"),
             .padding("0 var(--sw-space-lg) var(--sw-space-xl)"))
        rule("h1",
             .fontSize("1.4rem"),
             .margin("0"))
    }

    static let theme = css {
        rule(".search-status",
             .color("color-mix(in srgb, var(--sw-text) 60%, transparent)"),
             .margin("0"))
    }
}
