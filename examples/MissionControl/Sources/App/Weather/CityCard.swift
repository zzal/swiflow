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
        // SwiflowUI Card supplies the surface (token bg/shadow/radius/padding); the
        // card keeps a min-width so it tiles nicely in the wrapping grid.
        return Card(variant: .elevated, .style("min-width", "12.5rem")) {
            VStack(spacing: .sm) {
                HStack(spacing: .sm, align: .center, justify: .between) {
                    h2(city.name, .class("city-name"))
                    Button("✕", variant: .ghost, size: .sm,
                           .attr("aria-label", "Unpin \(city.name)")) { self.onUnpin() }
                }
                if let f = weather.data {
                    let wmo = wmoDescription(f.current.weatherCode)
                    HStack(spacing: .sm, align: .center) {
                        span(.class("temp")) {
                            text("\(Int(f.current.temperature.rounded()))\(f.currentUnits.temperature)")
                        }
                        span(.class("wmo"), .attr("title", wmo.label)) { text(wmo.emoji) }
                        if weather.isFetching {
                            Spinner(size: .sm, label: "Updating")
                        }
                    }
                    p(wmo.label, .class("wmo-label"))
                    if let high = f.daily.highs.first, let low = f.daily.lows.first {
                        p("H \(Int(high.rounded()))° · L \(Int(low.rounded()))° · wind \(Int(f.current.windSpeed.rounded())) km/h",
                          .class("range"))
                    }
                } else if weather.isLoading {
                    Spinner(size: .lg, label: "Loading weather")
                } else if weather.error != nil {
                    p("offline", .class("error"))
                }
            }
        }
    }
}
