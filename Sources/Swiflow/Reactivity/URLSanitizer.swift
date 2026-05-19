// Sources/Swiflow/Reactivity/URLSanitizer.swift

import Foundation

/// Validates and sanitizes URL values destined for the four URL-bearing
/// HTML attributes (`href`, `src`, `action`, `formaction`). Returns `nil`
/// for any value that fails the allowlist; callers (the DSL fold step)
/// drop the attribute when `nil` is returned.
///
/// **Security focus:** the default allowlist excludes `javascript:`,
/// `vbscript:`, `data:`, `blob:`, and any unknown scheme. The two most
/// commonly-needed-but-risky schemes (`data:`, `blob:`) have explicit
/// opt-in toggles so a calling application can re-enable them with a
/// loudly-named static property.
///
/// **Audit pattern:** every URL-bearing attribute that reaches the DOM
/// passes through `URLSanitizer.sanitize(_:)`. Search for that exact
/// symbol to enumerate every entry point. The `VNode.rawHTML(...)`
/// escape hatch is the only documented way to bypass.
public enum URLSanitizer {

    public static let defaultAllowedSchemes: Set<String> = [
        "http", "https", "mailto", "tel", "ftp",
    ]

    /// Configure these three properties once at application startup,
    /// before any render or concurrent `sanitize(_:)` call.
    /// `nonisolated(unsafe)` suppresses Swift's concurrency checker but
    /// does NOT add synchronisation — runtime mutation while a render is
    /// in flight is a data race.
    nonisolated(unsafe) public static var allowedSchemes: Set<String> = defaultAllowedSchemes

    nonisolated(unsafe) public static var allowDataURLs: Bool = false

    nonisolated(unsafe) public static var allowBlobURLs: Bool = false

    public static let urlAttributeNames: Set<String> = [
        "href", "src", "action", "formaction",
    ]

    public static func sanitize(_ rawValue: String) -> String? {
        let cleaned = stripControlAndLeadingWhitespace(rawValue)
        let decoded = decodeHTMLColonEntities(cleaned)

        if decoded.isEmpty || decoded.hasPrefix("#") {
            return rawValue
        }

        guard let scheme = extractScheme(decoded) else {
            return rawValue
        }

        let lowerScheme = scheme.lowercased()

        if lowerScheme == "data" {
            return allowDataURLs ? rawValue : nil
        }
        if lowerScheme == "blob" {
            return allowBlobURLs ? rawValue : nil
        }

        return allowedSchemes.contains(lowerScheme) ? rawValue : nil
    }

    // MARK: - Internals

    private static func stripControlAndLeadingWhitespace(_ s: String) -> String {
        let withoutControls = String(s.unicodeScalars.filter { scalar in
            let v = scalar.value
            return !(v < 0x20 || v == 0x7F)
        })
        return String(withoutControls.drop(while: { $0.isWhitespace }))
    }

    /// Decodes the literal colon entities only (`&#58;` decimal,
    /// `&#x3a;` / `&#x3A;` hex — the hex form is matched
    /// case-insensitively). Other colon encodings (`&colon;`,
    /// zero-padded `&#058;`, `&#x0003A;`) are intentionally left
    /// literal — DSL callers pass Swift strings, not HTML text, so
    /// only the exact obfuscations a hand-crafted attack would use
    /// need to be normalised.
    private static func decodeHTMLColonEntities(_ s: String) -> String {
        s.replacingOccurrences(of: "&#58;", with: ":")
         .replacingOccurrences(of: "&#x3a;", with: ":", options: .caseInsensitive)
    }

    private static func extractScheme(_ s: String) -> String? {
        guard let colonIndex = s.firstIndex(of: ":") else { return nil }
        let beforeColon = s[s.startIndex..<colonIndex]
        guard !beforeColon.isEmpty else { return nil }
        for char in beforeColon {
            let isAlpha = char.isLetter && char.isASCII
            let isDigit = char.isNumber && char.isASCII
            let isExtra = (char == "+" || char == "-" || char == ".")
            if !(isAlpha || isDigit || isExtra) {
                return nil
            }
        }
        if let first = beforeColon.first, !(first.isLetter && first.isASCII) {
            return nil
        }
        return String(beforeColon)
    }
}
