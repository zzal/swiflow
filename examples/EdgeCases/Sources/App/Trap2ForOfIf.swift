// Sources/App/Trap2ForOfIf.swift
import Swiflow

/// Trap 2: `for` of `if`. Each list item conditionally renders an inner node.
/// Toggling one item's flag must not recreate a sibling item's input.
@MainActor @Component
final class Trap2ForOfIf {
    @State var flags: [Bool] = [false, false, false]

    var body: VNode {
        section(.data("testid", "trap2")) {
            h2("2. for-of-if")
            for i in 0..<3 {
                div(.class("row"), .key("item-\(i)")) {
                    button("toggle \(i)", .data("testid", "trap2-toggle-\(i)"),
                           .on(.click) { self.flags[i].toggle() })
                    if flags[i] { span(.class("tag")) { text("[on]") } }
                    input(.attr("type", "text"), .data("testid", "trap2-input-\(i)"))
                }
            }
        }
    }
}
