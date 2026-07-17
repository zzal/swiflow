import Swiflow
import SwiflowUI

@Component
final class ToggleStory {
    @State var subscribed: Bool = false
    @State var name: String = ""

    var body: VNode {
        storyPage("Toggle",
                  blurb: "A switch — an IMMEDIATE on/off setting (like Dark mode, top-right), applied "
                       + "the moment it flips. For a value that's confirmed/submitted with a form, "
                       + "use Checkbox instead.") {
            variantSection("Switch", snippet: """
            Toggle("Subscribe to updates", isOn: $subscribed)
            """) {
                Card(variant: .plain) {
                    VStack(spacing: .md, align: .stretch) {
                        Toggle("Subscribe to updates", isOn: $subscribed)
                        p(subscribed ? "Subscribed — you'll hear from us." : "Not subscribed.")
                    }
                }
            }
            variantSection("Horizontal layout", snippet: """
            TextField("Name", text: $name, layout: .horizontal)
            Toggle("Subscribe to updates", isOn: $subscribed, layout: .horizontal)
            """) {
                Card(variant: .plain) {
                    VStack(spacing: .md, align: .stretch) {
                        TextField("Name", text: $name, layout: .horizontal)
                        Toggle("Subscribe to updates", isOn: $subscribed, layout: .horizontal)
                    }
                }
            }
        }
    }
}
