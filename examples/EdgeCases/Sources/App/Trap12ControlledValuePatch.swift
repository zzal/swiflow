// Sources/App/Trap12ControlledValuePatch.swift
import Swiflow

/// Trap 12: the complement of every other trap. Those use UNCONTROLLED inputs to
/// prove a node was *preserved* (a typed value only survives if the node wasn't
/// recreated). This one uses a CONTROLLED input — its value is bound to `@State`
/// via `.value($text)` — to prove the other direction: when state changes, the
/// reconciler must PATCH the live `.value` of the SAME node (the update path, not
/// the preserve path). A `showFirst` conditional sits before it so the controlled
/// input also has to survive reconciliation while bound.
@MainActor @Component
final class Trap12ControlledValuePatch {
    @State var text: String = "alpha"
    @State var showFirst: Bool = false

    var body: VNode {
        section(.data("testid", "trap12")) {
            h2("12. controlled input — value patched on state change")
            div(.class("row")) {
                button("set beta", .data("testid", "trap12-set-beta"),
                       .on(.click) { self.text = "beta" })
                button("uppercase", .data("testid", "trap12-upper"),
                       .on(.click) { self.text = self.text.uppercased() })
                button("toggle before", .data("testid", "trap12-toggle"),
                       .on(.click) { self.showFirst.toggle() })
            }
            if showFirst {
                p("conditional content is showing")
            }
            div(.class("row")) {
                label("Controlled:")
                input(.attr("type", "text"), .data("testid", "trap12-input"), .value($text))
            }
        }
    }
}
