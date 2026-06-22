// Sources/App/Weather/WeatherQueries.swift
import SwiflowQuery

#if canImport(JavaScriptKit)
import JavaScriptKit
#endif

/// Percent-encode a user-typed query for a URL. Foundation's
/// `addingPercentEncoding` isn't available under WASM, so this defers to the
/// browser's `encodeURIComponent`. (Host fallback is identity — the host
/// build only typechecks, it never fetches.)
func urlEncoded(_ s: String) -> String {
    #if canImport(JavaScriptKit)
    return JSObject.global.encodeURIComponent.function?(s).string ?? s
    #else
    return s
    #endif
}

/// Geocode a (debounced) city-name fragment. The caller gates on
/// `name.count >= 2`; `query()` is render-scoped, so a query simply not
/// observed this render drops its subscription — conditional calls are fine.
@QueryType struct CitySearchQuery: Query {
    let name: String

    // Transformed cache key (case-insensitive) — kept by hand; @Key derives keys
    // mechanically, so a `.lowercased()` key opts out of @Key marking. @QueryType
    // still synthesizes the `Query` conformance + `init(name:)`.
    var queryKey: QueryKey { ["geocode", .string(name.lowercased())] }
    /// Place names don't move; retyping the same prefix within the hour is a
    /// pure cache hit.
    var staleTime: Duration { .seconds(3600) }

    func fetch() async throws -> GeoSearchResponse {
        try await API.geocoding.get("/v1/search?name=\(urlEncoded(name))&count=5")
    }
}

/// Current conditions + today's range for one pinned city. Keyed on
/// (city id, unit) — `latitude`/`longitude` ride along as captured
/// dependencies, excluded from the key per the `Query` contract.
@QueryType(prefix: "weather") struct CurrentWeatherQuery: Query {
    @Key let city: City   // contributes .int(city.id) via City: QueryKeyConvertible
    @Key let unit: String   // "celsius" | "fahrenheit"

    var tags: Set<QueryTag> { ["weather"] }

    /// Fresh for a minute: re-renders, re-pins, and tab switches inside that
    /// window paint from cache with zero requests.
    var staleTime: Duration { .seconds(60) }
    /// Background refresh every 5 minutes while a card is on screen.
    var refetchInterval: Duration? { .seconds(300) }

    func fetch() async throws -> Forecast {
        try await API.forecast.get(
            "/v1/forecast?latitude=\(city.latitude)&longitude=\(city.longitude)"
            + "&current=temperature_2m,weather_code,wind_speed_10m"
            + "&daily=temperature_2m_max,temperature_2m_min"
            + "&timezone=auto&temperature_unit=\(unit)"
        )
    }
}

/// `City` contributes its stable `id` to a query key, so `@Key let city: City`
/// keys a weather query on the city without dragging lat/long into the cache slot.
extension City: QueryKeyConvertible {
    var keyComponents: [QueryKeyComponent] { [.int(id)] }
}

extension City {
    /// Starter pins (real Open-Meteo geocoding records, fetched 2026-06-11)
    /// so the dashboard shows live data before the first search.
    static let seeds: [City] = [
        City(id: 6077243, name: "Montréal", latitude: 45.50884, longitude: -73.58781,
             country: "Canada", admin1: "Quebec"),
        City(id: 1850147, name: "Tokyo", latitude: 35.6895, longitude: 139.69171,
             country: "Japan", admin1: "Tokyo"),
        City(id: 2267057, name: "Lisbon", latitude: 38.72509, longitude: -9.1498,
             country: "Portugal", admin1: "Lisbon District"),
    ]
}
