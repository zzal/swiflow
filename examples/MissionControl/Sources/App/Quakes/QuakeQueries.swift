// Sources/App/Quakes/QuakeQueries.swift
import SwiflowQuery

/// USGS publishes one feed per (magnitude floor × time window) pair, so the
/// two filter selects map 1:1 onto feed URLs — and each combination is
/// naturally its own cache entry.
@QueryType(prefix: "quakes") struct QuakeFeedQuery {
    @Key let magnitude: String   // "all" | "1.0" | "2.5" | "4.5" | "significant"
    @Key let window: String      // "hour" | "day" | "week"

    var tags: Set<QueryTag> { ["quakes"] }

    /// Poll every 30 s — earthquakes don't wait for a refresh button.
    var refetchInterval: Duration? { .seconds(30) }
    /// Anything younger than the polling cadence is fresh; switching filters
    /// back within 30 s renders instantly from cache without a refetch.
    var staleTime: Duration { .seconds(30) }

    func fetch() async throws -> QuakeFeed {
        try await API.usgs.get("/earthquakes/feed/v1.0/summary/\(magnitude)_\(window).geojson")
    }
}
