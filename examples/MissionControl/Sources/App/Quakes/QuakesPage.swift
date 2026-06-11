// Sources/App/Quakes/QuakesPage.swift
//
// Live USGS earthquake feed. Demonstrates:
// - a polling query (`refetchInterval` 30 s) whose data changes while you watch,
// - `isFetching` vs `isLoading` — the "⟳" pulses on background polls while the
//   already-rendered list stays put (stale-while-revalidate),
// - filter selects whose values are the query key — every (magnitude, window)
//   pair is its own cache entry, so flipping back is instant,
// - a bare `.task { }` ticker that keeps "n min ago" honest without refetching.
import Swiflow
import SwiflowDOM
import SwiflowQuery
import SwiflowUI

@MainActor @Component
final class QuakesPage {
    @State var magnitude: String = "2.5"
    @State var window: String = "day"
    /// Wall-clock anchor for relative timestamps, ticked by the bare `.task`.
    @State var nowMs: Double = 0

    var body: VNode {
        let feed = query(QuakeFeedQuery(magnitude: magnitude, window: window))
        return VStack(spacing: .md, .class("page")) {
            embed { NavBar() }

            HStack(spacing: .sm, align: .center, .class("toolbar")) {
                h1("🌐 Live seismic feed")
                if feed.isFetching {
                    span(.class("live-dot"), .attr("title", "refreshing")) { text("⟳") }
                }
            }

            HStack(spacing: .sm, align: .center, .class("filters")) {
                label("Magnitude", .attr("for", "mag"))
                // The `selected` attrs mirror the initial @State: at mount the
                // select's bound `value` property lands before its <option>
                // children, so without them the browser falls back to the
                // first option.
                select(.id("mag"), .selection($magnitude)) {
                    option("All", .attr("value", "all"))
                    option("M1.0+", .attr("value", "1.0"))
                    option("M2.5+", .attr("value", "2.5"), .attr("selected", ""))
                    option("M4.5+", .attr("value", "4.5"))
                    option("Significant", .attr("value", "significant"))
                }
                label("Window", .attr("for", "win"))
                select(.id("win"), .selection($window)) {
                    option("Past hour", .attr("value", "hour"))
                    option("Past day", .attr("value", "day"), .attr("selected", ""))
                    option("Past week", .attr("value", "week"))
                }
            }

            if let data = feed.data {
                p("\(data.metadata.count) events — updates every 30 s",
                  .class("feed-meta"))
                ul(.class("quake-list")) {
                    for quake in data.features {
                        quakeRow(quake, nowMs: nowMs)
                    }
                }
            } else if feed.isLoading {
                p("Listening to the planet…", .class("feed-meta"))
            } else if feed.error != nil {
                p("Couldn't reach the USGS feed — check your connection. Recovers automatically on refocus.",
                  .class("error"))
            }
        }
        // Bare `.task` = mount-scoped effect: tick the relative-time anchor
        // every 30 s. Cancellation on unmount makes Task.sleep throw, and the
        // isCancelled check exits the loop; the runtime would drop any stale
        // write anyway.
        .task {
            while !Task.isCancelled {
                self.nowMs = epochNowMs()
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
    }
}
