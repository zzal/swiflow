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
            variantSection("Badge sizes", snippet: """
            Badge("xs", size: .xs)
            Badge("sm", size: .sm)
            Badge("md")            // default
            Badge("lg", size: .lg)
            """) {
                HStack(spacing: .sm, align: .center) {
                    Badge("xs", variant: .accent, size: .xs)
                    Badge("sm", variant: .accent, size: .sm)
                    Badge("md", variant: .accent)
                    Badge("lg", variant: .accent, size: .lg)
                }
            }
            variantSection("Progress", snippet: """
            ProgressView(value: 0.6)
            ProgressView(value: 0.6, animated: true)   // macOS-style sheen sweep
            """) {
                ProgressView(value: 0.6)
                ProgressView(value: 0.6, animated: true)
                p("The Spinner and the animated progress sheen pause under "
                  + "prefers-reduced-motion (via --sw-anim-play); cards/badges/progress "
                  + "re-skin with the theme — flip Dark mode to see it.")
            }
        }
    }
}
