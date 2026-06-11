// Sources/App/API.swift
//
// HTTP clients + Decodable models for the two live APIs.
//
// Both APIs are free, keyless, and CORS-open:
//   - Open-Meteo  (forecast + geocoding) — https://open-meteo.com
//   - USGS earthquake feed               — https://earthquake.usgs.gov
//
// Decoding note: responses decode with JavaScriptKit's `JSValueDecoder`
// (see SwiflowFetcher), which has no key-decoding strategy — so every model
// spells out snake_case keys in explicit `CodingKeys`.
import SwiflowFetcher

#if canImport(JavaScriptKit)
import JavaScriptKit
#endif

// MARK: - Clients

enum API {
    /// Open-Meteo runs geocoding and forecasts on separate hosts.
    static let geocoding = HTTPClient(baseURL: "https://geocoding-api.open-meteo.com")
    static let forecast = HTTPClient(baseURL: "https://api.open-meteo.com")
    static let usgs = HTTPClient(baseURL: "https://earthquake.usgs.gov")
}

/// Wall-clock epoch milliseconds via JS `Date.now()` — Foundation's `Date`
/// isn't available under WASM. (Returns 0 on the host, which only typechecks
/// this target and never renders.)
@MainActor
func epochNowMs() -> Double {
    #if canImport(JavaScriptKit)
    return JSObject.global.Date.object?.now?().number ?? 0
    #else
    return 0
    #endif
}

// MARK: - Open-Meteo geocoding
// GET /v1/search?name={q}&count=5
// {"results":[{"id":6077243,"name":"Montreal","latitude":45.50884,
//   "longitude":-73.58781,"country":"Canada","admin1":"Quebec",...}], ...}
// `results` is absent entirely when nothing matches.

struct GeoSearchResponse: Decodable, Equatable, Sendable {
    let results: [City]?
}

struct City: Decodable, Equatable, Hashable, Sendable {
    let id: Int
    let name: String
    let latitude: Double
    let longitude: Double
    let country: String?
    let admin1: String?

    /// "Montreal, Quebec, Canada" — admin1/country are optional in the feed.
    var fullName: String {
        [name, admin1, country].compactMap(\.self).joined(separator: ", ")
    }
}

// MARK: - Open-Meteo forecast
// GET /v1/forecast?latitude=…&longitude=…
//     &current=temperature_2m,weather_code,wind_speed_10m
//     &daily=temperature_2m_max,temperature_2m_min
//     &timezone=auto&temperature_unit={celsius|fahrenheit}

struct Forecast: Decodable, Equatable, Sendable {
    let current: Current
    let currentUnits: CurrentUnits
    let daily: Daily

    enum CodingKeys: String, CodingKey {
        case current
        case currentUnits = "current_units"
        case daily
    }

    struct Current: Decodable, Equatable, Sendable {
        let temperature: Double
        let weatherCode: Int
        let windSpeed: Double

        enum CodingKeys: String, CodingKey {
            case temperature = "temperature_2m"
            case weatherCode = "weather_code"
            case windSpeed = "wind_speed_10m"
        }
    }

    struct CurrentUnits: Decodable, Equatable, Sendable {
        let temperature: String   // "°C" / "°F"

        enum CodingKeys: String, CodingKey {
            case temperature = "temperature_2m"
        }
    }

    struct Daily: Decodable, Equatable, Sendable {
        let highs: [Double]
        let lows: [Double]

        enum CodingKeys: String, CodingKey {
            case highs = "temperature_2m_max"
            case lows = "temperature_2m_min"
        }
    }
}

/// WMO weather interpretation codes (the `weather_code` field) → display.
/// Table per Open-Meteo's documentation.
func wmoDescription(_ code: Int) -> (emoji: String, label: String) {
    switch code {
    case 0:          ("☀️", "Clear sky")
    case 1:          ("🌤️", "Mainly clear")
    case 2:          ("⛅️", "Partly cloudy")
    case 3:          ("☁️", "Overcast")
    case 45, 48:     ("🌫️", "Fog")
    case 51, 53, 55: ("🌦️", "Drizzle")
    case 56, 57:     ("🌧️", "Freezing drizzle")
    case 61, 63, 65: ("🌧️", "Rain")
    case 66, 67:     ("🌧️", "Freezing rain")
    case 71, 73, 75: ("🌨️", "Snow")
    case 77:         ("🌨️", "Snow grains")
    case 80, 81, 82: ("🌦️", "Rain showers")
    case 85, 86:     ("🌨️", "Snow showers")
    case 95:         ("⛈️", "Thunderstorm")
    case 96, 99:     ("⛈️", "Thunderstorm with hail")
    default:         ("❓", "Unknown")
    }
}

// MARK: - USGS earthquake feed
// GET /earthquakes/feed/v1.0/summary/{magnitude}_{window}.geojson
// GeoJSON FeatureCollection; `properties.time` is epoch ms (exceeds Int32 —
// wasm32's Int — so it stays a Double), `mag`/`place` can be null.

struct QuakeFeed: Decodable, Equatable, Sendable {
    let metadata: Metadata
    let features: [Quake]

    struct Metadata: Decodable, Equatable, Sendable {
        let title: String
        let count: Int
    }
}

struct Quake: Decodable, Equatable, Sendable {
    let id: String
    let properties: Properties

    struct Properties: Decodable, Equatable, Sendable {
        let mag: Double?
        let place: String?
        let time: Double   // epoch milliseconds
        let url: String
    }
}
