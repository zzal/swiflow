// Sources/App/Trap5KeyedWithFragments.swift
import Swiflow

/// Trap 5: keyed elements interspersed with fragments. Swapping the keyed
/// items and toggling the conditional must reuse the keyed inputs (identity
/// preserved), with the fragments holding their positions.
@MainActor @Component
final class Trap5KeyedWithFragments {
    @State var order: [String] = ["a", "b"]
    @State var showX: Bool = false

    var body: VNode {
        section(.data("testid", "trap5")) {
            h2("5. keyed reorder with interspersed fragments")
            div(.class("row")) {
                button("swap", .data("testid", "trap5-swap"),
                       .on(.click) { self.order.reverse() })
                button("toggle x", .data("testid", "trap5-togglex"),
                       .on(.click) { self.showX.toggle() })
            }
            div {
                input(.attr("type", "text"), .data("testid", "trap5-input-\(order[0])"), .key("k-\(order[0])"))
                if showX { span(.class("tag"), .key("frag-x")) { text("[x]") } }
                input(.attr("type", "text"), .data("testid", "trap5-input-\(order[1])"), .key("k-\(order[1])"))
                for i in 0..<2 { span(.class("tag"), .key("f-\(i)")) { text(" f\(i) ") } }
            }
        }
    }
}
