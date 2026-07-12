import Swiflow
import SwiflowUI

@Component
final class NumberFieldStory {
    @State var rating: Double = 2.5
    @State var age: Int = 30

    var body: VNode {
        storyPage("NumberField",
                  blurb: "A native <input type=\"number\">: same label/error chrome as TextField, over Int or Double bindings.") {
            variantSection("Double with range", snippet: """
            NumberField("Rating", value: $rating, min: 0, max: 10, step: 0.5)
            """) {
                Card(variant: .plain) {
                    VStack(spacing: .md, align: .stretch) {
                        NumberField("Rating", value: $rating, min: 0, max: 10, step: 0.5)
                        p("value: \(rating)")
                    }
                }
            }
            variantSection("Int", snippet: """
            NumberField("Age", value: $age, min: 0, max: 120, step: 1)
            """) {
                Card(variant: .plain) {
                    VStack(spacing: .md, align: .stretch) {
                        NumberField("Age", value: $age, min: 0, max: 120, step: 1)
                        p("value: \(age)")
                    }
                }
            }
        }
    }
}
