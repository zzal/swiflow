// Sources/App/App.swift
//
// Mission Control — watching the planet live from Swift in the browser.
// Two routed tabs over free, keyless, CORS-open APIs:
//   /        Weather  — Open-Meteo forecast + geocoding
//   /quakes  Quakes   — USGS earthquake feed
import Swiflow
import SwiflowDOM
import SwiflowRouter

/// Root shell around the router. A `@Component` (unlike the `@main` entry
/// struct) so it can own app-wide `scopedStyles` — every routed page renders
/// inside it, so its descendant rules (see `App+Styles.swift`) reach them.
@Component
final class Shell {
    var body: VNode {
        embed {
            RouterRoot {
                Route("/") { WeatherPage() }
                Route("/quakes") { QuakesPage() }
            }
        }
    }
}

@main
struct App {
    @MainActor
    static func main() {
        Swiflow.render(into: "#app") { Shell() }
    }
}
