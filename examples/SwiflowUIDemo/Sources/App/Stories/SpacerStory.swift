import Swiflow
import SwiflowUI

@Component
final class SpacerStory {
    var body: VNode {
        storyPage("Spacer",
                  blurb: "A Spacer() between the buttons pushes them to opposite ends.") {
            variantSection("Push apart", snippet: """
            HStack(align: .center) {
                Button("Leading", variant: .secondary) {}
                Spacer()
                Button("Trailing", variant: .secondary) {}
            }
            """) {
                Card(variant: .plain) {
                    HStack(align: .center) {
                        Button("Leading", variant: .secondary) {}
                        Spacer()
                        Button("Trailing", variant: .secondary) {}
                    }
                }
            }
        }
    }
}
