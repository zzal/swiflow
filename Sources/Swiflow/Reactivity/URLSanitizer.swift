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

    private static func decodeHTMLColonEntities(_ s: String) -> String {
        s.replacingOccurrences(of: "&#58;", with: ":")
         .replacingOccurrences(of: "&#x3a;", with: ":", options: .caseInsensitive)
         .replacingOccurrences(of: "&#x3A;", with: ":")
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
