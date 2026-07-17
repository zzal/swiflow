import Swiflow
import SwiflowUI

@Component
final class RadioGroupStory {
    @State var plan: String = "Free"
    @State var name: String = ""

    var body: VNode {
        storyPage("RadioGroup",
                  blurb: "A <fieldset>/<legend> group of custom-drawn radios (identical pixels in "
                       + "every browser) over a Binding<String> — the native shared name gives "
                       + "roving keyboard focus for free.") {
            variantSection("Selection", snippet: """
            RadioGroup("Plan", selection: $plan, options: ["Free", "Pro", "Team"], size: .sm)
            """) {
                Card(variant: .plain) {
                    VStack(spacing: .md, align: .stretch) {
                        RadioGroup("Plan", selection: $plan, options: ["Free", "Pro", "Team"], size: .sm)
                        p("Selected plan: \(plan)")
                    }
                }
            }
            variantSection("Horizontal layout", snippet: """
            TextField("Name", text: $name, layout: .horizontal)
            RadioGroup("Plan", selection: $plan, options: ["Free", "Pro", "Team"], layout: .horizontal)
            """) {
                Card(variant: .plain) {
                    VStack(spacing: .md, align: .stretch) {
                        TextField("Name", text: $name, layout: .horizontal)
                        RadioGroup("Plan", selection: $plan, options: ["Free", "Pro", "Team"], layout: .horizontal)
                    }
                }
            }
        }
    }
}
