import Swiflow
import SwiflowUI

@Component
final class ButtonStory {
    // Knobs
    @State var variantName: String = "primary"
    @State var sizeName: String = "md"
    @State var disabled: Bool = false
    @State var label: String = "Click me"

    private var variant: ButtonVariant {
        switch variantName {
        case "secondary": .secondary
        case "ghost": .ghost
        case "danger": .danger
        default: .primary
        }
    }
    private var size: ControlSize {
        switch sizeName { case "sm": .sm; case "lg": .lg; default: .md }
    }

    var body: VNode {
        storyPage("Button",
                  blurb: "Variants and sizes are skinned entirely by --sw-* tokens.") {
            variantSection("Variants", snippet: """
            Button("Primary") {}
            Button("Secondary", variant: .secondary) {}
            Button("Ghost", variant: .ghost) {}
            Button("Danger", variant: .danger) {}
            Button("Disabled", disabled: true) {}
            """) {
                Card(variant: .plain) {
                    HStack(spacing: .md, align: .center) {
                        Button("Primary") {}
                        Button("Secondary", variant: .secondary) {}
                        Button("Ghost", variant: .ghost) {}
                        Button("Danger", variant: .danger) {}
                        Button(variant: .secondary, action: {}) { span(.attr("aria-hidden", true)) { text("↻") }; text("Retry") }
                        Button(variant: .ghost, .attr("aria-label", "Delete"), action: {}) { span(.attr("aria-hidden", true)) { text("🗑") } }
                        Button("Disabled", disabled: true) {}
                    }
                }
            }
            variantSection("Sizes", snippet: """
            Button("Small", size: .sm) {}
            Button("Medium", size: .md) {}
            Button("Large", size: .lg) {}
            """) {
                Card(variant: .plain) {
                    HStack(spacing: .md, align: .center) {
                        Button("Small", size: .sm) {}
                        Button("Medium", size: .md) {}
                        Button("Large", size: .lg) {}
                    }
                }
            }
            variantSection("Playground") {
                Card(variant: .outlined) {
                    VStack(spacing: .md, align: .stretch) {
                        TextField("Label", text: $label)
                        Select("Variant", selection: $variantName,
                               options: ["primary", "secondary", "ghost", "danger"])
                        RadioGroup("Size", selection: $sizeName,
                                   options: ["sm", "md", "lg"], size: .sm)
                        Toggle("Disabled", isOn: $disabled)
                        Divider()
                        HStack(align: .center) {
                            Button(label, variant: variant, size: size, disabled: disabled) {}
                        }
                    }
                }
            }
        }
    }
}
