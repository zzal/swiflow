// Tests/SwiflowTests/Reactivity/URLSanitizerTests.swift
import Testing
@testable import Swiflow

@Suite("URLSanitizer", .serialized)
struct URLSanitizerTests {

    @Test("Allows the default scheme set: http, https, mailto, tel, ftp")
    func allowsDefaultSchemes() {
        let allowed = [
            "http://example.com",
            "https://example.com/path?q=1",
            "mailto:user@example.com",
            "tel:+15551234",
            "ftp://ftp.example.com/file.zip",
        ]
        for url in allowed {
            #expect(URLSanitizer.sanitize(url) == url, "Expected allow for: \(url)")
        }
    }

    @Test("Allows relative URLs and fragment-only URLs")
    func allowsRelativeAndFragment() {
        let allowed = [
            "/path/to/page",
            "path/to/page",
            "../page",
            "#section",
            "#",
            "",
        ]
        for url in allowed {
            #expect(URLSanitizer.sanitize(url) == url, "Expected allow for relative/fragment: \(url)")
        }
    }

    @Test("Rejects javascript: scheme")
    func rejectsJavascript() {
        #expect(URLSanitizer.sanitize("javascript:alert(1)") == nil)
    }

    @Test("Rejects javascript: case-insensitively")
    func rejectsJavascriptCaseInsensitive() {
        #expect(URLSanitizer.sanitize("JAVASCRIPT:alert(1)") == nil)
        #expect(URLSanitizer.sanitize("JavaScript:alert(1)") == nil)
        #expect(URLSanitizer.sanitize("javaSCRIPT:alert(1)") == nil)
    }

    @Test("Rejects javascript: with leading whitespace and control characters")
    func rejectsJavascriptWithLeadingWhitespace() {
        #expect(URLSanitizer.sanitize("  javascript:alert(1)") == nil)
        #expect(URLSanitizer.sanitize("\tjavascript:alert(1)") == nil)
        #expect(URLSanitizer.sanitize("\njavascript:alert(1)") == nil)
        #expect(URLSanitizer.sanitize("\u{0001}javascript:alert(1)") == nil)
    }

    @Test("Rejects javascript: encoded with HTML entities")
    func rejectsJavascriptHTMLEntities() {
        #expect(URLSanitizer.sanitize("javascript&#58;alert(1)") == nil)
        #expect(URLSanitizer.sanitize("javascript&#x3A;alert(1)") == nil)
    }

    @Test("Rejects data: by default")
    func rejectsDataURLsByDefault() {
        #expect(URLSanitizer.sanitize("data:text/html,<script>alert(1)</script>") == nil)
        #expect(URLSanitizer.sanitize("data:image/png;base64,iVBORw0KGgo=") == nil)
    }

    @Test("Allows data: when allowDataURLs is true")
    func allowsDataURLsWhenOptedIn() {
        URLSanitizer.allowDataURLs = true
        defer { URLSanitizer.allowDataURLs = false }
        #expect(URLSanitizer.sanitize("data:image/png;base64,iVBORw0KGgo=") == "data:image/png;base64,iVBORw0KGgo=")
        #expect(URLSanitizer.sanitize("javascript:alert(1)") == nil)
    }

    @Test("Rejects blob: by default; allows when opted in")
    func blobURLOptIn() {
        #expect(URLSanitizer.sanitize("blob:https://example.com/uuid") == nil)
        URLSanitizer.allowBlobURLs = true
        defer { URLSanitizer.allowBlobURLs = false }
        #expect(URLSanitizer.sanitize("blob:https://example.com/uuid") == "blob:https://example.com/uuid")
    }

    @Test("Rejects vbscript: scheme")
    func rejectsVbscript() {
        #expect(URLSanitizer.sanitize("vbscript:msgbox(1)") == nil)
        #expect(URLSanitizer.sanitize("VBSCRIPT:msgbox(1)") == nil)
    }

    @Test("Custom allowedSchemes override the defaults")
    func customAllowedSchemes() {
        URLSanitizer.allowedSchemes = ["myscheme"]
        defer { URLSanitizer.allowedSchemes = URLSanitizer.defaultAllowedSchemes }
        #expect(URLSanitizer.sanitize("myscheme://anything") == "myscheme://anything")
        #expect(URLSanitizer.sanitize("https://example.com") == nil, "https no longer in allowlist")
    }

    @Test("applyAttributes drops javascript: href and keeps benign attributes")
    func applyAttributesDropsJavascriptHref() {
        let element = applyAttributes(tag: "a", [
            .attr("href", "javascript:alert(1)"),
            .class("link"),
        ])
        #expect(element.attributes["href"] == nil, "Expected javascript: href to be dropped from the bag")
        #expect(element.attributes["class"] == "link", "Class should pass through unchanged")
    }

    @Test("applyAttributes sanitizes case-variant attribute names — blocks unsafe, keeps safe")
    func applyAttributesCaseInsensitive() {
        let blocked = applyAttributes(tag: "a", [
            .attr("HREF", "javascript:alert(1)"),
        ])
        #expect(blocked.attributes["HREF"] == nil)

        let allowed = applyAttributes(tag: "a", [
            .attr("HREF", "https://example.com"),
        ])
        #expect(allowed.attributes["HREF"] == "https://example.com",
                "Case-variant attribute name must still pass benign URLs through")
    }

    @Test("applyAttributes keeps safe href + src + action + formaction")
    func applyAttributesKeepsSafeURLAttributes() {
        let element = applyAttributes(tag: "form", [
            .attr("action", "/submit"),
            .attr("formaction", "https://example.com/alt"),
        ])
        #expect(element.attributes["action"] == "/submit")
        #expect(element.attributes["formaction"] == "https://example.com/alt")
    }

    @Test("applyAttributes does NOT sanitize non-URL attributes (data-* etc.)")
    func applyAttributesPassesThroughNonURLAttrs() {
        let element = applyAttributes(tag: "div", [
            .attr("data-href", "javascript:alert(1)"),
            .attr("title", "javascript:alert(1)"),
        ])
        #expect(element.attributes["data-href"] == "javascript:alert(1)")
        #expect(element.attributes["title"] == "javascript:alert(1)")
    }
}
