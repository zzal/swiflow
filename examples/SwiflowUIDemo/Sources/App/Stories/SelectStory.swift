import Swiflow
import SwiflowUI

@Component
final class SelectStory {
    @State var color: String = ""

    var body: VNode {
        storyPage("Select",
                  blurb: "A labelled native <select> over a Binding<String>. Skinned end-to-end where "
                       + "Customizable Select is available (Chrome/Safari) — including the option "
                       + "picker and its drop-and-fade open animation — with a styled-trigger "
                       + "fallback elsewhere.") {
            variantSection("Selection", snippet: """
            Select("Favorite color", selection: $color, options: ["Red", "Green", "Blue"], placeholder: "Choose…")
            """) {
                Card(variant: .plain) {
                    VStack(spacing: .md, align: .stretch) {
                        Select("Favorite color", selection: $color, options: ["Red", "Green", "Blue"], placeholder: "Choose…")
                        if !color.isEmpty { p("Picked: \(color)") }
                    }
                }
            }
        }
    }
}
