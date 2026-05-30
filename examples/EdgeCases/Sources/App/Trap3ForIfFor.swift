// Sources/App/Trap3ForIfFor.swift
import Swiflow

/// Trap 3: three-level imbrication — outer keyed list, per-item conditional,
/// inner keyed sub-list. Mutating one item's inner list must leave the other
/// outer items' inputs untouched.
@MainActor @Component
final class Trap3ForIfFor {
    @State var counts: [Int] = [1, 1]

    var body: VNode {
        section(.data("testid", "trap3")) {
            h2("3. for-of-if-of-for")
            for outer in 0..<2 {
                div(.class("row"), .key("outer-\(outer)")) {
                    input(.attr("type", "text"), .data("testid", "trap3-input-\(outer)"))
                    button("inner+1", .data("testid", "trap3-add-\(outer)"),
                           .on(.click) { self.counts[outer] += 1 })
                    if counts[outer] > 0 {
                        ul {
                            for inner in 0..<counts[outer] {
                                li(.key("inner-\(outer)-\(inner)")) { text("• row \(inner)") }
                            }
                        }
                    }
                }
            }
        }
    }
}
