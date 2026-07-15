// Tests/SwiflowUITests/SkeletonTests.swift
// Skeleton is a stateless shimmering placeholder — Badge's shape (a skinned
// `<span>`) plus a `lines:` multi-line text variant. Decorative (aria-hidden),
// and the shimmer is gated on --sw-anim-play so prefers-reduced-motion freezes
// it for free (the exact Spinner precedent).
import Testing
import Swiflow
@testable import SwiflowUI

@MainActor private func el(_ node: VNode?) -> ElementData? {
    if case .element(let data)? = node { return data }
    return nil
}

@Suite("Skeleton")
@MainActor
struct SkeletonTests {
    @Test("block: renders a span.sw-skeleton with inline width/height styles") func renders() {
        let s = el(Skeleton(width: "40px", height: "12px"))!
        #expect(s.tag == "span")
        #expect(s.attributes["class"] == "sw-skeleton")
        #expect(s.style["width"] == "40px")
        #expect(s.style["height"] == "12px")
    }

    @Test("block: defaults to width 100% / height 1em") func defaults() {
        let s = el(Skeleton())!
        #expect(s.style["width"] == "100%")
        #expect(s.style["height"] == "1em")
    }

    @Test("block: is decorative — aria-hidden=true") func ariaHidden() {
        #expect(el(Skeleton())!.attributes["aria-hidden"] == "true")
    }

    @Test("block: no inline border-radius when radius is nil (sheet default wins)") func radiusNilOmitsInlineStyle() {
        let s = el(Skeleton())!
        #expect(s.style["border-radius"] == nil)
    }

    @Test("block: radius sets an inline border-radius override") func radiusOverride() {
        let s = el(Skeleton(radius: "50%"))!
        #expect(s.style["border-radius"] == "50%")
    }

    @Test("block: caller attributes and class merge") func callerMerge() {
        let s = el(Skeleton(width: "40px", height: "40px", radius: "50%", .class("avatar"), .attr("id", "thumb")))!
        #expect(s.attributes["class"] == "sw-skeleton avatar")
        #expect(s.attributes["id"] == "thumb")
    }

    @Test("lines: renders a div.sw-skeleton-text container with N .sw-skeleton children") func linesContainer() {
        let node = Skeleton(lines: 3)
        let container = el(node)!
        #expect(container.tag == "div")
        #expect(container.attributes["class"] == "sw-skeleton-text")
        #expect(container.children.count == 3)
        for child in container.children {
            #expect(el(child)!.attributes["class"] == "sw-skeleton")
        }
    }

    @Test("lines: container is also decorative — aria-hidden=true") func linesAriaHidden() {
        #expect(el(Skeleton(lines: 3))!.attributes["aria-hidden"] == "true")
    }

    @Test("lines: 0 and negative counts render zero children (no crash)") func linesNonPositive() {
        #expect(el(Skeleton(lines: 0))!.children.count == 0)
        #expect(el(Skeleton(lines: -2))!.children.count == 0)
    }

    @Test("lines: caller attributes and class merge onto the container") func linesCallerMerge() {
        let c = el(Skeleton(lines: 2, .class("hero"), .attr("id", "card-body")))!
        #expect(c.attributes["class"] == "sw-skeleton-text hero")
        #expect(c.attributes["id"] == "card-body")
    }

    @Test("stylesheet: shimmer gates on --sw-anim-play, sheet-driven border-radius, last line is shortened") func stylesheet() {
        let css = skeletonStyleSheet.cssString(scopeClass: "")
        #expect(css.contains(".sw-skeleton"))
        #expect(css.contains("animation-play-state: var(--sw-anim-play)"))
        #expect(css.contains("@keyframes sw-skeleton-shimmer"))
        #expect(css.contains("border-radius: var(--sw-radius-sm)"))
        #expect(css.contains(".sw-skeleton-text"))
        #expect(css.contains(".sw-skeleton-text > .sw-skeleton:last-child"))
        #expect(css.contains("var(--sw-surface-2)"))
        // Backdrop blending: two stacked layers with CONSTANT keywords whose paint
        // self-neutralizes in the wrong scheme (multiply×white = screen×black =
        // identity) — mix-blend-mode can't ride light-dark() and a media query
        // wouldn't follow a forced root color-scheme.
        #expect(css.contains("mix-blend-mode: multiply"))
        #expect(css.contains("mix-blend-mode: screen"))
        #expect(css.contains("light-dark(var(--sw-surface-2), #fff)"))
        #expect(css.contains("light-dark(#000, var(--sw-surface-2))"))
    }
}
