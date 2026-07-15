import Swiflow
import SwiflowUI
import SwiflowRouter

@Component
final class PopoverStory {
    var body: VNode {
        storyPage("Popover",
                  blurb: "Popover is the general-purpose sibling of Dropdown: same native Popover-API "
                       + "recipe (popover=\"auto\" + CSS anchor positioning, so it's top-layer with "
                       + "native ESC + light-dismiss), but no baked-in menu-item shape — any single "
                       + "trigger element, any content. Popover wires popovertarget/anchor-name onto "
                       + "the trigger you pass in, so its own classes/attrs (like a Button's sw-btn "
                       + "skin) survive untouched.") {
            variantSection("Anchored panel — one per placement", snippet: """
            Popover(placement: .top) {
                Button("Top", variant: .secondary) {}
            } content: {
                p("A short note anchored above the trigger.")
                embed { Link("/component/modal", "See Modal too") }
            }
            """) {
                HStack(spacing: .md, align: .center) {
                    Popover(placement: .top) {
                        Button("Top", variant: .secondary) {}
                    } content: {
                        p("A short note anchored above the trigger.")
                        embed { Link("/component/modal", "See Modal too") }
                    }
                    Popover(placement: .bottom) {
                        Button("Bottom", variant: .secondary) {}
                    } content: {
                        p("A short note anchored below the trigger.")
                        embed { Link("/component/modal", "See Modal too") }
                    }
                    Popover(placement: .leading) {
                        Button("Leading", variant: .secondary) {}
                    } content: {
                        p("A short note anchored before the trigger.")
                        embed { Link("/component/modal", "See Modal too") }
                    }
                    Popover(placement: .trailing) {
                        Button("Trailing", variant: .secondary) {}
                    } content: {
                        p("A short note anchored after the trigger.")
                        embed { Link("/component/modal", "See Modal too") }
                    }
                }
            }
            variantSection("Offset — a standoff from the trigger", snippet: """
            Popover(placement: .bottom, offset: 3) {
                Button("3px off", variant: .secondary) {}
            } content: {
                p("Opens with a small gap to the trigger (Tooltip's standoff).")
            }
            """) {
                HStack(spacing: .md, align: .center) {
                    Popover(placement: .bottom, offset: 3) {
                        Button("3px off", variant: .secondary) {}
                    } content: {
                        p("Opens with a small gap to the trigger (Tooltip's standoff).")
                    }
                    Popover(placement: .bottom, offset: 8) {
                        Button("8px off", variant: .secondary) {}
                    } content: {
                        p("Any distance works — offset is just pixels.")
                    }
                }
            }
        }
    }
}
