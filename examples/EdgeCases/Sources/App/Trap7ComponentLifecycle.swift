// Sources/App/Trap7ComponentLifecycle.swift
import Swiflow
import SwiflowWeb
import JavaScriptKit

/// A child whose mount/unmount bumps shared counters via callbacks, so the test
/// can assert onAppear/onDisappear fire exactly once per toggle.
@MainActor @Component
final class LifecycleChild {
    let onUp: () -> Void
    let onDown: () -> Void
    init(onUp: @escaping () -> Void, onDown: @escaping () -> Void) {
        self.onUp = onUp; self.onDown = onDown
    }
    var body: VNode { span(.class("tag")) { text("child-mounted") } }
    func onAppear() { onUp() }
    func onDisappear() { onDown() }
}

/// A sibling component holding its OWN @State counter. If the reconciler
/// recreates it while the LifecycleChild churns, this counter resets to 0.
@MainActor @Component
final class Keeper {
    @State var n: Int = 0
    var body: VNode {
        div(.class("row")) {
            button("keeper+1", .data("testid", "trap7-keeper-inc"), .on(.click) { self.n += 1 })
            span(.data("testid", "trap7-keeper-count")) { text("\(n)") }
        }
    }
}

/// Trap 7: a component inside an emptying fragment, beside a stateful sibling
/// component. Toggling the child off/on must fire onDisappear/onAppear exactly
/// once each and must NOT reset the sibling Keeper's @State.
@MainActor @Component
final class Trap7ComponentLifecycle {
    @State var showChild: Bool = false
    @State var appears: Int = 0
    @State var disappears: Int = 0

    var body: VNode {
        section(.data("testid", "trap7")) {
            h2("7. component in an emptying fragment + lifecycle")
            div(.class("row")) {
                button("toggle child", .data("testid", "trap7-toggle"),
                       .on(.click) { self.showChild.toggle() })
                span(.data("testid", "trap7-appears")) { text("up:\(appears)") }
                span(.data("testid", "trap7-disappears")) { text("down:\(disappears)") }
            }
            if showChild {
                embed { LifecycleChild(onUp: { self.appears += 1 }, onDown: { self.disappears += 1 }) }
            }
            embed { Keeper() }
        }
    }
}
