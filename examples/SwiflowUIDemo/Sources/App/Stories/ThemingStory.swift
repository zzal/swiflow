import Swiflow
import SwiflowUI

@Component
final class ThemingStory {
    var body: VNode {
        storyPage("Scoped theming",
                  blurb: "The right-hand group is wrapped in Theme(.accent(\"#dc2626\"), .radius(\"2px\")). "
                       + "One override re-points --sw-accent; the whole family (fill, ghost text, badge "
                       + "tint, focus ring) and the radius follow — scoped to that subtree only. The "
                       + "wrapper uses display:contents, so it sits inline in the row with no layout shift.") {
            variantSection("Theme(.accent, .radius)", snippet: """
            Button("Default accent") {}
            Theme(.accent("#dc2626"), .radius("2px")) {
                HStack(spacing: .md, align: .center) {
                    Button("Branded primary") {}
                    Button("Branded ghost", variant: .ghost) {}
                    Badge("Tagged", variant: .accent)
                }
            }
            """) {
                Card(variant: .plain) {
                    HStack(spacing: .md, align: .center) {
                        Button("Default accent") {}
                        Theme(.accent("#dc2626"), .radius("2px")) {
                            HStack(spacing: .md, align: .center) {
                                Button("Branded primary") {}
                                Button("Branded ghost", variant: .ghost) {}
                                Badge("Tagged", variant: .accent)
                            }
                        }
                    }
                }
            }
        }
    }
}
