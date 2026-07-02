// Sources/App/Weather/WeatherPage+Styles.swift
import Swiflow

extension WeatherPage {
    @MainActor static var scopedStyles: CSSSheet? = layout + theme

    static let layout = css {
        host {
            .display("block");
            .maxWidth("860px");
            .margin("0 auto");
            .padding("0 var(--sw-space-lg) var(--sw-space-xl)");
        }
        rule("h1") {
            .fontSize("1.4rem");
            .margin("0");
        }
        rule(".search-results") {
            .listStyle("none");
            .margin("0");
            .padding("var(--sw-space-xs)");
            .display("flex");
            .flexDirection("column");
            .gap("var(--sw-space-xs)");
        }
    }

    static let theme = css {
        rule(".search-results") {
            .background("var(--sw-surface)");
            .border("1px solid color-mix(in srgb, var(--sw-text) 15%, transparent)");
            .borderRadius("var(--sw-radius)");
        }
        rule(".search-status") {
            .color("color-mix(in srgb, var(--sw-text) 60%, transparent)");
            .margin("0");
        }
        rule(".error") {
            .color("light-dark(#b91c1c, #fca5a5)");
            .margin("0");
        }
    }
}
