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
import SwiflowStore
import SwiflowUI

@MainActor @Component
final class WeatherPage {
    @State var searchText: String = ""
    @State var debouncedText: String = ""
    @State var pinned: [City] = City.seeds
    @State var unit: String = "celsius"

    /// Pins outlive this page: the router destroys `WeatherPage` on every
    /// navigation, so the list is persisted to IndexedDB and rehydrated on
    /// mount. `City.seeds` is just the first-ever-visit default.
    private let store = PersistentStore()
    private static let pinnedKey = "pinned-cities"

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
        // Runs once per mount (i.e. on every return to this page): rehydrate the
        // saved pins, then refresh the geolocated first card.
        .task { await self.bootstrap() }
    }

    func pin(_ city: City) {
        if !pinned.contains(where: { $0.id == city.id }) {
            pinned.append(city)
        }
        searchText = ""
        debouncedText = ""
        persist()
    }

    func unpin(_ city: City) {
        pinned.removeAll { $0.id == city.id }
        persist()
    }

    // MARK: - Persistence + geolocation

    /// Restore persisted pins (keeping `City.seeds` only on a first-ever visit),
    /// then ask the browser for the current location and pin it first.
    private func bootstrap() async {
        if let saved = try? await store.load([City].self, forKey: Self.pinnedKey) {
            pinned = saved
        }
        guard let fix = await Geolocation.currentPosition(),
              let here = try? await reverseGeocodedCity(latitude: fix.latitude, longitude: fix.longitude) else {
            return   // unavailable / denied / lookup failed → keep the list as-is
        }
        // Keep "current location" unique and first; replace any prior fix.
        pinned.removeAll { $0.isCurrentLocation }
        pinned.insert(here, at: 0)
        persist()
    }

    /// Fire-and-forget save — `@State` mutations already repainted; persistence
    /// trails behind without blocking the UI.
    private func persist() {
        Task { try? await store.save(pinned, forKey: Self.pinnedKey) }
    }
}
