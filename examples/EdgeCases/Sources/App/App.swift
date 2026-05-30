// Sources/App/App.swift
import Swiflow
import SwiflowWeb

/// EdgeLab — adversarial reconciliation stress harness. Each embedded trap is a
/// self-contained <section data-testid="trapN"> exercising one nesting/identity
/// edge case, with a sentinel that only survives if the reconciler reuses nodes
/// rather than recreating them. See the design spec.
@MainActor @Component
final class EdgeLab {
    var body: VNode {
        div(.class("lab")) {
            h2("Swiflow reconciliation traps")
            embed { Trap1CondBeforeFocus() }
            embed { Trap2ForOfIf() }
            embed { Trap3ForIfFor() }
            embed { Trap4LoopInCond() }
            embed { Trap5KeyedWithFragments() }
            embed { Trap6TwoAdjacentConds() }
            embed { Trap7ComponentLifecycle() }
            embed { Trap8RapidCycle() }
            embed { Trap9KeyedItemsInnerState() }
            embed { Trap10RawSpread() }
            embed { Trap11DynamicList() }
        }
    }
}

@main
struct App {
    @MainActor
    static func main() {
        Swiflow.render(into: "#app") { EdgeLab() }
    }
}
