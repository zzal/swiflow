// Tests/SwiflowUITests/AvatarTests.swift
// Avatar is a stateless component, Badge's shape: an <img> when `src` is
// given (via `.src`, sanitized just like TextLink's `href`), else an
// initials <span role="img" aria-label=name>.
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

@Suite("Avatar")
@MainActor
struct AvatarTests {
    @Test("src given → renders an <img> with the sw-avatar classes, src, and alt=name") func rendersImage() {
        let a = el(Avatar("Ada Lovelace", src: "https://example.com/ada.png"))!
        #expect(a.tag == "img")
        #expect(a.attributes["class"] == "sw-avatar sw-avatar--md sw-avatar--circle")
        #expect(a.attributes["src"] == "https://example.com/ada.png")
        #expect(a.attributes["alt"] == "Ada Lovelace")
    }

    @Test("no src → renders an initials <span role=img aria-label=name>") func rendersInitialsSpan() {
        let node = Avatar("Ada Lovelace")
        let a = el(node)!
        #expect(a.tag == "span")
        #expect(a.attributes["class"] == "sw-avatar sw-avatar--md sw-avatar--circle sw-avatar--initials")
        #expect(a.attributes["role"] == "img")
        #expect(a.attributes["aria-label"] == "Ada Lovelace")
        #expect(allText(node) == "AL")
    }

    @Test("avatarInitials: first letter of up-to-two whitespace-separated words, uppercased") func initialsTwoWords() {
        #expect(avatarInitials("Ada Lovelace") == "AL")
    }

    @Test("avatarInitials: single word → its first letter") func initialsOneWord() {
        #expect(avatarInitials("Ada") == "A")
    }

    @Test("avatarInitials: empty/whitespace-only name → \"?\"") func initialsBlank() {
        #expect(avatarInitials("") == "?")
        #expect(avatarInitials("   ") == "?")
    }

    @Test("avatarInitials: lowercase input is uppercased") func initialsUppercases() {
        #expect(avatarInitials("ada lovelace") == "AL")
    }

    @Test("size maps to the modifier class") func sizeClasses() {
        #expect(el(Avatar("Ada", size: .sm))!.attributes["class"] == "sw-avatar sw-avatar--sm sw-avatar--circle sw-avatar--initials")
        #expect(el(Avatar("Ada", size: .lg))!.attributes["class"] == "sw-avatar sw-avatar--lg sw-avatar--circle sw-avatar--initials")
    }

    @Test("shape maps to the modifier class") func shapeClasses() {
        #expect(el(Avatar("Ada", shape: .rounded))!.attributes["class"] == "sw-avatar sw-avatar--md sw-avatar--rounded sw-avatar--initials")
        #expect(el(Avatar("Ada", shape: .square))!.attributes["class"] == "sw-avatar sw-avatar--md sw-avatar--square sw-avatar--initials")
    }

    @Test("a javascript: src is scrubbed by URLSanitizer, not passed through raw") func sanitizesJavascriptSrc() {
        let raw = "javascript:alert(1)"
        let a = el(Avatar("Ada", src: raw))!
        #expect(a.attributes["src"] != raw)
    }

    @Test("caller attributes and class merge onto the image variant") func callerMergeImage() {
        let a = el(Avatar("Ada", src: "https://example.com/ada.png", .class("ring"), .attr("id", "avatar-1")))!
        #expect(a.attributes["class"] == "sw-avatar sw-avatar--md sw-avatar--circle ring")
        #expect(a.attributes["id"] == "avatar-1")
    }

    @Test("caller attributes and class merge onto the initials variant") func callerMergeInitials() {
        let a = el(Avatar("Ada", .class("ring"), .attr("id", "avatar-2")))!
        #expect(a.attributes["class"] == "sw-avatar sw-avatar--md sw-avatar--circle sw-avatar--initials ring")
        #expect(a.attributes["id"] == "avatar-2")
    }

    @Test("stylesheet: token-driven sizes/weight, shape variants") func stylesheet() {
        let css = avatarStyleSheet.cssString(scopeClass: "")
        #expect(css.contains(".sw-avatar"))
        #expect(css.contains("var(--sw-font-weight-medium)"))
        #expect(css.contains("var(--sw-surface-2)"))
        #expect(css.contains(".sw-avatar--sm"))
        #expect(css.contains(".sw-avatar--md"))
        #expect(css.contains(".sw-avatar--lg"))
        #expect(css.contains(".sw-avatar--circle"))
        #expect(css.contains(".sw-avatar--rounded"))
        #expect(css.contains(".sw-avatar--square"))
        #expect(css.contains("var(--sw-radius)"))
    }
}
