import Swiflow
import SwiflowUI

@Component
final class TooltipStory {
    var body: VNode {
        storyPage("Tooltip",
                  blurb: "Tooltip wraps any trigger — hover or focus to reveal. Placement defaults to .top; "
                       + "pass placement: .bottom (or .leading / .trailing) to anchor it on another side. "
                       + "Pure CSS — no JS, no z-index juggling.") {
            variantSection("Placement", snippet: """
            Tooltip("Saved to your library") { Button("Hover or focus me", variant: .secondary) {} }
            Tooltip("Appears below the trigger", placement: .bottom) { Button("Below") {} }
            """) {
                Card(variant: .plain) {
                    HStack(spacing: .md, align: .center) {
                        Tooltip("Saved to your library") { Button("Hover or focus me", variant: .secondary) {} }
                        Tooltip("Appears below the trigger", placement: .bottom) { Button("Below") {} }
                    }
                }
            }
            variantSection("Arrow", snippet: """
            Tooltip("Points at the trigger", arrow: true) { Button("Arrow on top", variant: .secondary) {} }
            Tooltip("From below", placement: .bottom, arrow: true) { Button("Arrow below") {} }
            Tooltip("Sideways too", placement: .trailing, arrow: true) { Button("Trailing") {} }
            """) {
                Card(variant: .plain) {
                    HStack(spacing: .md, align: .center) {
                        Tooltip("Points at the trigger", arrow: true) { Button("Arrow on top", variant: .secondary) {} }
                        Tooltip("From below", placement: .bottom, arrow: true) { Button("Arrow below") {} }
                        Tooltip("Sideways too", placement: .trailing, arrow: true) { Button("Trailing") {} }
                    }
                }
            }
        }
    }
}
