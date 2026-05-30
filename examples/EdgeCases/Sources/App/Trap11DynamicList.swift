// Sources/App/Trap11DynamicList.swift
import Swiflow

/// Trap 11: dynamic keyed list with Add +1 / +100 (front and back), Remove,
/// Clear, Swap. Bulk front-insertion stresses insertBefore + LIS; existing rows
/// must NOT be recreated (their typed values + node identity survive), which
/// also proves the diff is minimal (not re-placing the whole list).
@MainActor @Component
final class Trap11DynamicList {
    @State var rows: [Int] = []
    @State var nextId: Int = 0

    private func add(_ count: Int, front: Bool) {
        let ids = (0..<count).map { _ -> Int in let id = nextId; nextId += 1; return id }
        if front { rows.insert(contentsOf: ids, at: 0) } else { rows.append(contentsOf: ids) }
    }

    var body: VNode {
        section(.data("testid", "trap11")) {
            h2("11. dynamic keyed list (add/remove/swap)")
            div(.class("row")) {
                button("+1 front", .data("testid", "trap11-add1-front"), .on(.click) { self.add(1, front: true) })
                button("+100 front", .data("testid", "trap11-add100-front"), .on(.click) { self.add(100, front: true) })
                button("+1 back", .data("testid", "trap11-add1-back"), .on(.click) { self.add(1, front: false) })
                button("remove first", .data("testid", "trap11-removefirst"),
                       .on(.click) { if !self.rows.isEmpty { self.rows.removeFirst() } })
                button("swap ends", .data("testid", "trap11-swap"),
                       .on(.click) { if self.rows.count >= 2 { self.rows.swapAt(0, self.rows.count - 1) } })
                button("clear", .data("testid", "trap11-clear"), .on(.click) { self.rows = [] })
                span(.data("testid", "trap11-count")) { text("\(rows.count)") }
            }
            ul(.data("testid", "trap11-list")) {
                for id in rows {
                    li(.key("r-\(id)"), .class("row")) {
                        span(.class("tag")) { text("#\(id) ") }
                        input(.attr("type", "text"), .data("testid", "trap11-input-\(id)"))
                    }
                }
            }
        }
    }
}
