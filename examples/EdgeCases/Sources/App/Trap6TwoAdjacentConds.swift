// Sources/App/Trap6TwoAdjacentConds.swift
import Swiflow

/// Trap 6: two adjacent conditionals before a sentinel input, inside a div that
/// also has a keyed sibling (forces the keyed path → exercises the structural-
/// sibling bucketKey fix). The input must survive all four a/b combinations.
@Component
final class Trap6TwoAdjacentConds {
    @State var a: Bool = false
    @State var b: Bool = false

    var body: VNode {
        section(.data("testid", "trap6")) {
            h2("6. two adjacent conditionals (bucketKey)")
            div(.class("row")) {
                button("toggle a", .data("testid", "trap6-a"), .on(.click) { self.a.toggle() })
                button("toggle b", .data("testid", "trap6-b"), .on(.click) { self.b.toggle() })
            }
            div {
                span(.class("tag"), .key("anchor")) { text("keyed-anchor ") }
                if a { span(.class("tag"), .key("cond-a")) { text("[a]") } }
                if b { span(.class("tag"), .key("cond-b")) { text("[b]") } }
                input(.attr("type", "text"), .data("testid", "trap6-input"), .key("sentinel"))
            }
        }
    }
}
