// Tests/SwiflowUITests/FeedbackTests.swift
// M5 display components — Spinner, ProgressView, Card, Badge. All stateless with
// no event handlers, so no ambient registry is needed (unlike the form controls).
import Testing
import Swiflow
@testable import SwiflowUI

@MainActor private func el(_ node: VNode?) -> ElementData? {
    if case .element(let data)? = node { return data }
    return nil
}

@MainActor private func allText(_ node: VNode) -> String {
    switch node {
    case .text(let s):                        return s
    case .element(let d):                     return d.children.map(allText).joined()
    case .fragment(let xs):                   return xs.map(allText).joined()
    case .environmentOverride(_, let child):  return allText(child)
    default:                                  return ""
    }
}

@Suite("Spinner")
@MainActor
struct SpinnerTests {
    @Test("renders a role=status span with size class and an accessible label") func renders() {
        let s = el(Spinner())!
        #expect(s.tag == "span")
        #expect(s.attributes["class"] == "sw-spinner sw-spinner--md")
        #expect(s.attributes["role"] == "status")
        #expect(s.attributes["aria-label"] == "Loading")
    }

    @Test("size + custom label lower as expected") func sizeAndLabel() {
        let s = el(Spinner(size: .lg, label: "Loading results"))!
        #expect(s.attributes["class"] == "sw-spinner sw-spinner--lg")
        #expect(s.attributes["aria-label"] == "Loading results")
    }

    @Test("stylesheet gates the spin on --sw-anim-play so reduced-motion freezes it") func stylesheet() {
        let css = spinnerStyleSheet.cssString(scopeClass: "")
        #expect(css.contains("animation-play-state: var(--sw-anim-play)"))
        #expect(css.contains("@keyframes sw-spin"))
        #expect(css.contains("var(--sw-accent)"))
    }
}

@Suite("ProgressView")
@MainActor
struct ProgressViewTests {
    @Test("renders a native <progress> with the value and max=1") func renders() {
        let p = el(ProgressView(value: 0.6))!
        #expect(p.tag == "progress")
        #expect(p.attributes["class"] == "sw-progress")
        #expect(p.attributes["value"] == "0.6")
        #expect(p.attributes["max"] == "1")
    }

    @Test("value is clamped to 0...1") func clamps() {
        #expect(el(ProgressView(value: 1.5))!.attributes["value"] == "1.0")
        #expect(el(ProgressView(value: -0.5))!.attributes["value"] == "0.0")
    }

    @Test("stylesheet styles the native progress track + value, token-driven") func stylesheet() {
        let css = progressStyleSheet.cssString(scopeClass: "")
        #expect(css.contains("::-webkit-progress-value"))
        #expect(css.contains("::-moz-progress-bar"))
        #expect(css.contains("var(--sw-accent)"))
        #expect(css.contains("var(--sw-surface-2)"))
    }
}

@Suite("Card")
@MainActor
struct CardTests {
    @Test("renders a surfaced div with the variant class, keeping children") func renders() {
        let node = Card { h3("Title"); p("Body") }
        let c = el(node)!
        #expect(c.tag == "div")
        #expect(c.attributes["class"] == "sw-card sw-card--elevated")   // default elevated
        #expect(c.children.count == 2)
        #expect(allText(node).contains("Title"))
    }

    @Test("outlined variant + caller class merge") func outlinedAndCaller() {
        let c = el(Card(variant: .outlined, .class("hero")) { text("x") })!
        #expect(c.attributes["class"] == "sw-card sw-card--outlined hero")
    }

    @Test("stylesheet: elevated uses --sw-shadow, outlined uses --sw-border, on --sw-surface") func stylesheet() {
        let css = cardStyleSheet.cssString(scopeClass: "")
        #expect(css.contains("background-color: var(--sw-surface)"))
        #expect(css.contains(".sw-card--elevated { box-shadow: var(--sw-shadow); }"))
        #expect(css.contains("var(--sw-border)"))
    }
}

@Suite("Badge")
@MainActor
struct BadgeTests {
    @Test("renders a span pill with the label and default neutral variant") func renders() {
        let node = Badge("New")
        let b = el(node)!
        #expect(b.tag == "span")
        #expect(b.attributes["class"] == "sw-badge sw-badge--neutral")
        #expect(allText(node) == "New")
    }

    @Test("variant maps to the modifier class") func variant() {
        #expect(el(Badge("3", variant: .accent))!.attributes["class"] == "sw-badge sw-badge--accent")
        #expect(el(Badge("!", variant: .danger))!.attributes["class"] == "sw-badge sw-badge--danger")
    }

    @Test("stylesheet uses soft color-mix tints (no extra text tokens)") func stylesheet() {
        let css = badgeStyleSheet.cssString(scopeClass: "")
        #expect(css.contains("color-mix(in oklab, var(--sw-danger)"))
        #expect(css.contains("var(--sw-surface-2)"))   // neutral
    }
}
