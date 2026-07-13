import Swiflow
import SwiflowUI

@Component
final class ToggleButtonGroupStory {
    @State var align: String = "left"
    @State var formats: Set<String> = ["bold"]

    var body: VNode {
        storyPage("ToggleButtonGroup",
                  blurb: "A segmented control of role=group buttons (aria-pressed) — String-keyed "
                       + "like RadioGroup/Select, in single- and multi-select flavors sharing one "
                       + "lowering. No roving focus: buttons are independently tabbable — for strict "
                       + "single-select with roving, use RadioGroup or Tabs instead.") {
            variantSection("Single-select", snippet: """
            @State var align = "left"
            …
            ToggleButtonGroup(selection: $align, options: ["left", "center", "right"])
            """) {
                VStack(spacing: .md, align: .stretch) {
                    ToggleButtonGroup(selection: $align, options: ["left", "center", "right"])
                    p("Aligned: \(align)")
                }
            }
            variantSection("Multi-select", snippet: """
            @State var formats: Set<String> = ["bold"]
            …
            ToggleButtonGroup(selection: $formats, options: ["bold", "italic", "underline"])
            """) {
                VStack(spacing: .md, align: .stretch) {
                    ToggleButtonGroup(selection: $formats, options: ["bold", "italic", "underline"])
                    p("Active: \(formats.sorted().joined(separator: ", "))")
                }
            }
        }
    }
}
