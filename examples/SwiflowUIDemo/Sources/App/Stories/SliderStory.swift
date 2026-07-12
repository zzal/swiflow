import Swiflow
import SwiflowUI

@Component
final class SliderStory {
    @State var volume: Double = 0.5
    @State var rating: Double = 5

    var body: VNode {
        storyPage("Slider",
                  blurb: "A native <input type=\"range\">: same label/error chrome as NumberField, styled over the accent token.") {
            variantSection("Volume", snippet: """
            Slider("Volume", value: $volume)
            """) {
                Card(variant: .plain) {
                    VStack(spacing: .md, align: .stretch) {
                        Slider("Volume", value: $volume)
                        p("value: \(volume)")
                    }
                }
            }
            variantSection("Stepped 0...10", snippet: """
            Slider("Rating", value: $rating, in: 0...10, step: 1)
            """) {
                Card(variant: .plain) {
                    VStack(spacing: .md, align: .stretch) {
                        Slider("Rating", value: $rating, in: 0...10, step: 1)
                        p("value: \(rating)")
                    }
                }
            }
        }
    }
}
