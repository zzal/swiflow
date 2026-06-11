// Sources/App/Weather/WeatherPage.swift
//
// Pinned-city weather over Open-Meteo. Demonstrates:
// - `.task(rerunOn:)` as a debouncer — 300 ms after the last keystroke the
//   raw input text is committed to `debouncedText`; superseded sleeps are
//   cancelled and their writes dropped by the runtime,
// - a conditional, text-keyed geocoding query (one request per settled
//   prefix, cached for an hour),
// - per-card weather queries keyed on (city, unit) — toggling °C → °F
//   refetches, toggling back paints instantly from cache,
// - SwiflowUI stacks + tokens for the whole layout.
import Swiflow
import SwiflowDOM
import SwiflowQuery
import SwiflowUI

@MainActor @Component
final class WeatherPage {
    @State var searchText: String = ""
    @State var debouncedText: String = ""
    @State var pinned: [City] = City.seeds
    @State var unit: String = "celsius"

    var body: VNode {
        let results: QueryState<GeoSearchResponse>? =
            debouncedText.count >= 2 ? query(CitySearchQuery(name: debouncedText)) : nil

        return VStack(spacing: .md, .class("page")) {
            embed { NavBar() }

            HStack(spacing: .sm, align: .center, .class("toolbar")) {
                h1("🌍 Weather")
                select(.class("unit-select"), .selection($unit)) {
                    option("°C", .attr("value", "celsius"))
                    option("°F", .attr("value", "fahrenheit"))
                }
            }

            VStack(spacing: .xs, .class("search-box")) {
                input(.attr("type", "search"),
                      .attr("placeholder", "Search a city to pin…"),
                      .value($searchText))
                if let results {
                    if let cities = results.data?.results, !cities.isEmpty {
                        ul(.class("search-results")) {
                            for city in cities {
                                li(.key("hit-\(city.id)")) {
                                    button(city.fullName, .class("search-hit"),
                                           .on(.click) { self.pin(city) })
                                }
                            }
                        }
                    } else if results.isLoading {
                        p("Searching…", .class("search-status"))
                    } else if results.error != nil {
                        p("Search unavailable — check your connection.", .class("error"))
                    } else {
                        p("No matches for “\(debouncedText)”.", .class("search-status"))
                    }
                }
            }

            HStack(spacing: .md, .class("card-grid"), .style("flex-wrap", "wrap")) {
                for city in pinned {
                    // Embedded instances are reused at a (type, key) position —
                    // the factory runs on first mount only, so a changed prop
                    // never reaches a live instance. Encoding `unit` in the
                    // embed key remounts the card on toggle; the cache (keyed
                    // on city + unit) makes the swap back instant.
                    div(.key("city-\(city.id)")) {
                        embed("card-\(city.id)-\(unit)") {
                            CityCard(city: city, unit: self.unit,
                                     onUnpin: { self.unpin(city) })
                        }
                    }
                }
            }
            if pinned.isEmpty {
                p("Nothing pinned — search above to add a city.", .class("search-status"))
            }
        }
        // Debounce: each keystroke re-keys this task; the previous sleep is
        // cancelled and only a 300 ms-settled value reaches `debouncedText`.
        .task(rerunOn: searchText) {
            try? await Task.sleep(nanoseconds: 300_000_000)
            self.debouncedText = self.searchText
        }
    }

    func pin(_ city: City) {
        if !pinned.contains(where: { $0.id == city.id }) {
            pinned.append(city)
        }
        searchText = ""
        debouncedText = ""
    }

    func unpin(_ city: City) {
        pinned.removeAll { $0.id == city.id }
    }
}
