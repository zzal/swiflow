import Swiflow
import SwiflowUI

@Component
final class StacksStory {
    var body: VNode {
        storyPage("Stacks",
                  blurb: "HStack/VStack with token spacing. Change --sw-space-md "
                       + "in index.html's <style> to reskin every gap at once.") {
            variantSection("Horizontal, .md spacing", snippet: """
            HStack(spacing: .md, align: .center) {
                Button("One") {}; Button("Two") {}; Button("Three") {}
            }
            """) {
                Card(variant: .plain) {
                    HStack(spacing: .md, align: .center) {
                        Button("One") {}; Button("Two") {}; Button("Three") {}
                    }
                }
            }
        }
    }
}
