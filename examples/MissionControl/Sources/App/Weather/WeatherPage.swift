// Sources/App/Weather/WeatherPage.swift
//
// Pinned-city weather over Open-Meteo. Demonstrates:
// - SwiflowUI's async `Autocomplete(loader:)` as the city search — it owns
//   the debounce, keystroke cancellation, and Searching / error / empty
//   panel states that this page used to hand-roll,
// - a consume-and-clear `Binding`: committing a suggestion pins the city
//   and resets the field instead of holding a selection,
// - per-card weather queries keyed on (city, unit) — toggling °C → °F
//   refetches, toggling back paints instantly from cache,
// - SwiflowUI stacks + tokens for the whole layout.
import Swiflow
import SwiflowDOM
import SwiflowQuery
import SwiflowStore
import SwiflowUI

@Component
final class WeatherPage {
    @State var pinned: [City] = City.seeds
    @State var unit: String = "celsius"

    /// The cities behind the latest Autocomplete suggestions, keyed by option
    /// value (the stringified geocoding id), so a committed selection resolves
    /// back to the full record. Plain var — nothing renders from it.
    private var searchHits: [String: City] = [:]

    /// Pins and the unit toggle outlive this page: the router destroys
    /// `WeatherPage` on every navigation, so they're persisted to IndexedDB and
    /// rehydrated on mount. `City.seeds` / "celsius" are just first-visit defaults.
    private let store = PersistentStore()
    private static let pinnedKey = "pinned-cities"
    private static let unitKey = "weather-unit"

    var body: VNode {
        VStack(spacing: .md, .class("page")) {
            embed { NavBar() }

            HStack(spacing: .sm, align: .center, .class("toolbar")) {
                h1("🌍 Weather")
                Select("Units", selection: $unit, options: [
                    SelectOption("celsius", "°C"),
                    SelectOption("fahrenheit", "°F"),
                ])
            }

            // Strict select-from-list combobox over the geocoder. The binding
            // never holds a value: a commit pins the city and the empty `get`
            // hands the field back cleared, ready for the next search.
            Autocomplete("Search cities",
                         selection: Binding(
                             get: { "" },
                             set: { id in
                                 if let city = self.searchHits[id] { self.pin(city) }
                             }),
                         loader: { q in try await self.searchCities(q) },
                         placeholder: "Search a city to pin…",
                         minChars: 2)

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
        // Runs once per mount (i.e. on every return to this page): rehydrate the
        // saved pins, then refresh the geolocated first card.
        .task { await self.bootstrap() }
    }

    /// Autocomplete loader: geocode the (already debounced) query and remember
    /// the `City` behind each option so a commit can pin the full record, not
    /// just its id. Place names don't move, so no cache layer is needed here —
    /// Autocomplete's cancellation already collapses rapid keystrokes.
    private func searchCities(_ q: String) async throws -> [SelectOption] {
        let response: GeoSearchResponse =
            try await API.geocoding.get("/v1/search?name=\(urlEncoded(q))&count=5")
        let cities = response.results ?? []
        for city in cities { searchHits[String(city.id)] = city }
        return cities.map { SelectOption(String($0.id), $0.fullName) }
    }

    func pin(_ city: City) {
        if !pinned.contains(where: { $0.id == city.id }) {
            pinned.append(city)
        }
        persist()
    }

    func unpin(_ city: City) {
        pinned.removeAll { $0.id == city.id }
        persist()
    }

    /// Persist the unit toggle whenever it changes. `onChange(of:)` seeds
    /// silently on the first call and fires only on a real change, so it never
    /// clobbers the value `bootstrap()` rehydrates.
    func onChange() {
        onChange(of: unit, key: "unit") { newUnit in
            Task { try? await self.store.save(newUnit, forKey: Self.unitKey) }
        }
    }

    // MARK: - Persistence + geolocation

    /// Restore persisted pins + unit (keeping the defaults only on a first-ever
    /// visit), then ask the browser for the current location and pin it first.
    private func bootstrap() async {
        if let saved = try? await store.load([City].self, forKey: Self.pinnedKey) {
            pinned = saved
        }
        if let savedUnit = try? await store.load(String.self, forKey: Self.unitKey) {
            unit = savedUnit
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
