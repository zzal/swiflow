// Sources/App/Quakes/QuakeRow.swift
import Swiflow
import SwiflowDOM
import SwiflowUI

/// One feed row. A plain VNode factory (not a component) so the list can key
/// rows directly with `.key(quake.id)`.
@MainActor
func quakeRow(_ quake: Quake, nowMs: Double) -> VNode {
    let mag = quake.properties.mag
    return li(.key(quake.id), .class("quake-row")) {
        // SwiflowUI Badge for the magnitude pill; `justify-self` keeps it left in
        // the row's grid column (Badge brings its own pill styling + token colors).
        Badge(mag.map { "M \(($0 * 10).rounded() / 10)" } ?? "M ?",
              variant: magnitudeBadge(mag),
              .style("justify-self", "start"))
        span(.class("place")) { text(quake.properties.place ?? "Unknown location") }
        span(.class("when")) { text(relativeTime(fromMs: quake.properties.time, nowMs: nowMs)) }
    }
}

/// Severity bucket → Badge variant: calm below M3, watchful to M5, alarming above.
/// The default theme has no amber/warning token, so "watchful" maps to `.accent`.
func magnitudeBadge(_ mag: Double?) -> BadgeVariant {
    switch mag ?? 0 {
    case ..<3:   .success
    case ..<5:   .accent
    default:     .danger
    }
}

/// "just now" / "12 min ago" / "3 h ago" / "2 d ago". Clamps negative deltas
/// (clock skew between USGS and the client) to "just now".
func relativeTime(fromMs: Double, nowMs: Double) -> String {
    let minutes = Int(max(0, nowMs - fromMs) / 60_000)
    switch minutes {
    case 0:        return "just now"
    case ..<60:    return "\(minutes) min ago"
    case ..<1440:  return "\(minutes / 60) h ago"
    default:       return "\(minutes / 1440) d ago"
    }
}
