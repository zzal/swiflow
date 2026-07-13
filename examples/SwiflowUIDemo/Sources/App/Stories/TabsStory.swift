import Swiflow
import SwiflowUI

@Component
final class TabsStory {
    @State var tab: String = "overview"

    var body: VNode {
        storyPage("Tabs",
                  blurb: "A WAI-ARIA tablist bound to a Binding<ID> selection. Automatic "
                       + "activation: ←/→ move between tabs and wrap, Home/End jump to the "
                       + "ends, and moving focus immediately selects the target tab (its "
                       + "panel swaps and focus follows) — Tab itself is left alone, so it "
                       + "still leaves the tablist for the next element. All tabs' panels "
                       + "render up front (render-all); the inactive ones are simply hidden, "
                       + "so panel state/ARIA stay stable across selection changes.") {
            variantSection("Three tabs", snippet: """
            @State var tab = "overview"
            …
            Tabs(selection: $tab) {
                Tab("Overview", id: "overview") {
                    p("A quick summary of the project.")
                }
                Tab("Details", id: "details") {
                    p("Everything the overview left out.")
                }
                Tab("Settings", id: "settings") {
                    p("Preferences that affect this view.")
                }
            }
            """) {
                Card(variant: .plain) {
                    Tabs(selection: $tab) {
                        Tab("Overview", id: "overview") {
                            p("A quick summary of the project.")
                        }
                        Tab("Details", id: "details") {
                            p("Everything the overview left out.")
                        }
                        Tab("Settings", id: "settings") {
                            p("Preferences that affect this view.")
                        }
                    }
                }
            }
        }
    }
}
