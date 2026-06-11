// Sources/App/Weather/CityCard.swift
import Swiflow
import SwiflowDOM
import SwiflowQuery
import SwiflowUI

/// One pinned city. Holds no `@State` of its own — the weather lives in the
/// query cache under (city id, unit), which is what makes unpin → re-pin
/// inside `staleTime` paint instantly.
@MainActor @Component
final class CityCard {
    let city: City
    let unit: String
    let onUnpin: () -> Void

    init(city: City, unit: String, onUnpin: @escaping () -> Void) {
        self.city = city
        self.unit = unit
        self.onUnpin = onUnpin
    }

    var body: VNode {
        let weather = query(CurrentWeatherQuery(city: city, unit: unit))
        return VStack(spacing: .sm, .class("city-card")) {
            HStack(spacing: .sm, align: .center, justify: .between) {
                h2(city.name, .class("city-name"))
                button("✕", .class("unpin"),
                       .attr("aria-label", "Unpin \(city.name)"),
                       .on(.click) { self.onUnpin() })
            }
            if let f = weather.data {
                let wmo = wmoDescription(f.current.weatherCode)
                HStack(spacing: .sm, align: .center) {
                    span(.class("temp")) {
                        text("\(Int(f.current.temperature.rounded()))\(f.currentUnits.temperature)")
                    }
                    span(.class("wmo"), .attr("title", wmo.label)) { text(wmo.emoji) }
                    if weather.isFetching {
                        span(.class("live-dot")) { text("⟳") }
                    }
                }
                p(wmo.label, .class("wmo-label"))
                if let high = f.daily.highs.first, let low = f.daily.lows.first {
                    p("H \(Int(high.rounded()))° · L \(Int(low.rounded()))° · wind \(Int(f.current.windSpeed.rounded())) km/h",
                      .class("range"))
                }
            } else if weather.isLoading {
                p("…", .class("temp"))
            } else if weather.error != nil {
                p("offline", .class("error"))
            }
        }
    }
}
