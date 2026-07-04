// Tests/SwiflowTests/DiffTests/NestedStructuralSpliceTests.swift
//
// Regression: a component whose body is an `environmentOverride` wrapping a
// child component (RouterRoot's exact shape) crashed on child-type swap when
// it had a real DOM ancestor — both the component-update arm AND the
// environmentOverride arm spliced removeChild+appendChild for the same swap,
// and the driver's second removeChild threw NotFoundError. It stayed latent
// while routers sat at the render root (domAncestorHandle == nil there; the
// renderer's replaceMount owns root swaps) and surfaced the moment the
// scope-class carrier (#137) gave a router a DOM ancestor.
//
// The rule under test: an arm splices only when its body update returned a
// WHOLESALE replacement (a fresh MountNode) — a same-reference return means
// placement was already reconciled deeper.
import Testing
@testable import Swiflow

@Suite("Diff — nested structural splice (router-under-element)")
@MainActor
struct NestedStructuralSpliceTests {

    final class PageA: Component {
        var body: VNode { .element(ElementData(tag: "section")) }
    }
    final class PageB: Component {
        var body: VNode { .element(ElementData(tag: "article")) }
    }

    /// RouterRoot's shape: body = environmentOverride(routed component).
    final class MiniRouter: Component {
        var showA = true
        var body: VNode {
            let routed: VNode = showA
                ? .component(.init(PageA.self) { PageA() })
                : .component(.init(PageB.self) { PageB() })
            return .environmentOverride(EnvironmentValues(), routed)
        }
    }

    private func removeChildPatches(_ patches: [Patch]) -> [(parent: Int, child: Int)] {
        patches.compactMap { p in
            if case .removeChild(let parent, let child) = p { return (parent, child) }
            return nil
        }
    }

    private func appendChildPatches(_ patches: [Patch]) -> [(parent: Int, child: Int)] {
        patches.compactMap { p in
            if case .appendChild(let parent, let child) = p { return (parent, child) }
            return nil
        }
    }

    @Test("Route swap under a DOM ancestor emits exactly one removeChild + one appendChild")
    func routeSwapUnderElementSplicesOnce() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let router = MiniRouter()

        // div > MiniRouter(component) > envOverride > PageA — the div is the
        // DOM ancestor both structural arms would (wrongly, doubly) splice at.
        func tree() -> VNode {
            .element(ElementData(tag: "div", children: [
                .component(.init(MiniRouter.self) { router }),
            ]))
        }

        let r1 = diff(mounted: nil, next: tree(), handles: handles, handlers: handlers)

        // Navigate: PageA → PageB.
        router.showA = false
        let r2 = diff(mounted: r1.newMountTree, next: tree(), handles: handles, handlers: handlers)

        let removes = removeChildPatches(r2.patches)
        let appends = appendChildPatches(r2.patches)
        #expect(removes.count == 1,
                "old page must be removed exactly once — a duplicate removeChild throws NotFoundError in the driver (got \(removes))")
        #expect(appends.count == 1,
                "new page must be appended exactly once (got \(appends))")
    }
}
