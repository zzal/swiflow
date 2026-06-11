// Sources/App/App.swift
//
// Mission Control — watching the planet live from Swift in the browser.
// Two routed tabs over free, keyless, CORS-open APIs:
//   /        Weather  — Open-Meteo forecast + geocoding
//   /quakes  Quakes   — USGS earthquake feed
import Swiflow
import SwiflowDOM
import SwiflowRouter

@main
struct App {
    @MainActor
    static func main() {
        Swiflow.render(into: "#app") {
            RouterRoot {
                Route("/") { WeatherPage() }
                Route("/quakes") { QuakesPage() }
            }
        }
    }
}
