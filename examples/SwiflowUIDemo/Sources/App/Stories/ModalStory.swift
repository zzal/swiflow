import Swiflow
import SwiflowUI

@Component
final class ModalStory {
    @State var showSettings: Bool = false
    @State var notifyByEmail: Bool = true

    var body: VNode {
        storyPage("Modal",
                  blurb: "Modal is the general-purpose sibling of Alert/Prompt: same native "
                       + "<dialog>.showModal() machinery (top layer, backdrop, focus trap, ESC-to-close), "
                       + "but no baked-in title-required/actions-slot opinion — an optional title, a "
                       + "size (.sm/.md/.lg), and arbitrary content. Unlike Alert, dismissOnBackdrop "
                       + "defaults to true: a generic modal is a casual overlay, so clicking outside "
                       + "to leave is the expected affordance. Reach for Alert/Prompt instead when you "
                       + "specifically need a confirm dialog or a single text-input prompt.") {
            variantSection("A settings modal", snippet: """
            Modal(isPresented: $showSettings, title: "Settings", size: .lg) {
                Toggle("Notify me by email", isOn: self.$notifyByEmail)
                HStack(spacing: .md, align: .center) {
                    Spacer()
                    Button("Close") { self.showSettings = false }
                }
            }
            """) {
                Button("Settings…", variant: .secondary) { self.showSettings = true }
                Modal(isPresented: $showSettings, title: "Settings", size: .lg) {
                    Toggle("Notify me by email", isOn: self.$notifyByEmail)
                    HStack(spacing: .md, align: .center) {
                        Spacer()
                        Button("Close") { self.showSettings = false }
                    }
                }
            }
        }
    }
}
