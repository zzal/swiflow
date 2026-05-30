// Sources/App/Trap4LoopInCond.swift
import Swiflow

/// Trap 4: a loop nested inside a conditional, with a <details open> sentinel
/// AFTER it. Toggling the whole loop on/off must not recreate the details
/// (its open state must survive), and refilled items appear before it.
@MainActor @Component
final class Trap4LoopInCond {
    @State var showList: Bool = true

    var body: VNode {
        section(.data("testid", "trap4")) {
            h2("4. loop inside a conditional")
            button("toggle list", .data("testid", "trap4-toggle"),
                   .on(.click) { self.showList.toggle() })
            if showList {
                ul {
                    for i in 0..<3 { li(.key("l-\(i)")) { text("loop item \(i)") } }
                }
            }
            details(.data("testid", "trap4-details")) {
                summary("sentinel disclosure")
                p("the open state here must survive toggling the loop above")
            }
        }
    }
}
