// Tests/SwiflowUITests/FieldSlugTests.swift
import Testing
@testable import SwiflowUI

@Suite("fieldSlug")
struct FieldSlugTests {
    @Test("lowercases and hyphenates on non-alphanumeric runs") func basic() {
        #expect(fieldSlug("Dark Mode") == "dark-mode")
        #expect(fieldSlug("Email notifications") == "email-notifications")
        #expect(fieldSlug("Favorite Color") == "favorite-color")
    }

    @Test("collapses punctuation; digits stay") func punctuationAndNumbers() {
        #expect(fieldSlug("2FA / MFA!") == "2fa-mfa")
    }

    @Test("empty or all-punctuation input slugs to empty; the fallback overload substitutes") func emptyFallsBackViaOverload() {
        #expect(fieldSlug("") == "")
        #expect(fieldSlug("!!!") == "")
        #expect(fieldSlug("", fallback: "toggle") == "toggle")
        #expect(fieldSlug("!!!", fallback: "checkbox") == "checkbox")
    }

    @Test("non-empty input ignores the fallback") func nonEmptyIgnoresFallback() {
        #expect(fieldSlug("Plan", fallback: "radiogroup") == "plan")
    }
}
