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
        }
    }
}
