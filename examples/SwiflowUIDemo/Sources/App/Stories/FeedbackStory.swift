import Swiflow
import SwiflowUI

@Component
final class FeedbackStory {
    var body: VNode {
        storyPage("Feedback & display",
                  blurb: "Cards, badges, spinners and progress — all skinned by --sw-* tokens; "
                       + "flip Dark mode (top-right) to see them re-skin.") {
            variantSection("Cards & badges", snippet: """
            Card {
                h3("Elevated Card")
                p("A surfaced container with a token shadow.")
                HStack(spacing: .sm, align: .center) {
                    Spinner()
                    Badge("New", variant: .accent)
                    Badge("3")
                }
            }
            Card(variant: .outlined) {
                h3("Outlined Card")
                p("Bordered instead of shadowed.")
                HStack(spacing: .sm, align: .center) {
                    Badge("Error", variant: .danger)
                    Badge("Done", variant: .success)
                    Badge("Warn", variant: .warning)
                    Badge("Info", variant: .info)
                    Badge("Muted")
                }
            }
            """) {
                Grid(columns: 2, spacing: .md) {
                    Card {
                        h3("Elevated Card")
                        p("A surfaced container with a token shadow.")
                        HStack(spacing: .sm, align: .center) {
                            Spinner()
                            Badge("New", variant: .accent)
                            Badge("3")
                        }
                    }
                    Card(variant: .outlined) {
                        h3("Outlined Card")
                        p("Bordered instead of shadowed.")
                        HStack(spacing: .sm, align: .center) {
                            Badge("Error", variant: .danger)
                            Badge("Done", variant: .success)
                            Badge("Warn", variant: .warning)
                            Badge("Info", variant: .info)
                            Badge("Muted")
                        }
                    }
                }
            }
            variantSection("Progress", snippet: """
            ProgressView(value: 0.6)
            """) {
                ProgressView(value: 0.6)
                p("The Spinner pauses under prefers-reduced-motion (via --sw-anim-play); "
                  + "cards/badges/progress re-skin with the theme — flip Dark mode to see it.")
            }
        }
    }
}
