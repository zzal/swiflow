import Swiflow
import SwiflowUI

/// A simple checkmark — hand-authored, single-color (`stroke="currentColor"`),
/// the shape `Icon`'s mask takes on.
private let checkSVG = "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16' fill='none' "
    + "stroke='currentColor' stroke-width='1.75' stroke-linecap='round' stroke-linejoin='round'>"
    + "<path d='M3 8l4 4 6-8'/></svg>"

/// A simple gear/settings glyph, same single-color contract.
private let gearSVG = "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16' fill='none' "
    + "stroke='currentColor' stroke-width='1.5' stroke-linecap='round' stroke-linejoin='round'>"
    + "<circle cx='8' cy='8' r='2.25'/>"
    + "<path d='M8 1.5v2M8 12.5v2M1.5 8h2M12.5 8h2M3.6 3.6l1.4 1.4M11 11l1.4 1.4M3.6 12.4l1.4-1.4M11 5l1.4-1.4'/>"
    + "</svg>"

/// A simple "close" X, used in the labeled (icon-only) example below.
private let closeSVG = "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16' fill='none' "
    + "stroke='currentColor' stroke-width='1.75' stroke-linecap='round'>"
    + "<path d='M4 4l8 8M12 4l-8 8'/></svg>"

@Component
final class IconStory {
    var body: VNode {
        storyPage("Icon",
                  blurb: "A stateless, single-color SVG seam: a <span> masked to a caller-supplied "
                       + "<svg> string via CSS mask/-webkit-mask, filled with currentColor. Apps bring "
                       + "their own icons — there's no bundled icon set.") {
            variantSection("Sizes", snippet: """
            Icon(checkSVG, size: .sm)
            Icon(checkSVG, size: .md)
            Icon(checkSVG, size: .lg)
            """) {
                HStack(spacing: .md, align: .center) {
                    Icon(checkSVG, size: .sm)
                    Icon(checkSVG, size: .md)
                    Icon(checkSVG, size: .lg)
                }
            }
            variantSection("Tinted", snippet: """
            Icon(gearSVG, size: .lg, .style("color", Token.accent.css))
            """) {
                p("The mask only carries alpha — the icon always renders in currentColor. "
                  + "Tint it with .style(\"color\", …) or nest it under a colored parent.")
                Icon(gearSVG, size: .lg, .style("color", Token.accent.css))
            }
            variantSection("Decorative vs. labeled", snippet: """
            // Decorative — adjacent text already conveys the meaning; aria-hidden, no role.
            HStack(spacing: .sm, align: .center) {
                Icon(checkSVG)
                Text("Saved")
            }

            // Labeled — the icon IS the accessible name; role="img" + aria-label, no aria-hidden.
            Icon(closeSVG, label: "Close")
            """) {
                VStack(spacing: .sm, align: .stretch) {
                    HStack(spacing: .sm, align: .center) {
                        Icon(checkSVG)
                        Text("Saved")
                    }
                    Icon(closeSVG, label: "Close")
                }
            }
        }
    }
}
