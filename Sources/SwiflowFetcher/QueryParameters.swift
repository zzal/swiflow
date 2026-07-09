// Sources/SwiflowFetcher/QueryParameters.swift
//
// Typed URL query parameters with owned percent-encoding. Pure Swift — no
// Foundation (unavailable under WASM), no JavaScriptKit — so encoding is
// identical on every platform and fully host-testable, like `JSONValue`.
// Before this, callers hand-concatenated query strings and shipped their own
// `encodeURIComponent` shims; every unescaped interpolation was a latent bug.

/// A scalar value for one URL query parameter.
///
/// Literal-expressible, so constant parameters read naturally and only
/// dynamic values need explicit case wrapping — the same convention as
/// `JSONValue`:
///
/// ```swift
/// let hits: SearchResponse = try await api.get("/v1/search", query: [
///     "name": .string(userTypedQuery),   // percent-encoded for you
///     "count": 5,
/// ])
/// ```
public enum HTTPQueryValue: Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
}

extension HTTPQueryValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
}
extension HTTPQueryValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) { self = .int(value) }
}
extension HTTPQueryValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) { self = .double(value) }
}
extension HTTPQueryValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) { self = .bool(value) }
}

extension HTTPQueryValue {
    /// The value's textual form, before percent-encoding. Non-finite doubles
    /// render as `NaN`/`Infinity`/`-Infinity`, matching what the browser's
    /// `URLSearchParams` produces for the same values.
    var text: String {
        switch self {
        case .string(let s): return s
        case .int(let i):    return String(i)
        case .double(let d):
            guard d.isFinite else { return d.isNaN ? "NaN" : (d > 0 ? "Infinity" : "-Infinity") }
            return String(d)
        case .bool(let b):   return b ? "true" : "false"
        }
    }
}

/// Percent-encoding and query-string assembly for `HTTPClient`'s `query:`
/// parameters.
enum QueryStringEncoding {
    /// RFC 3986 percent-encoding of one query component: unreserved
    /// characters (ALPHA / DIGIT / `-` / `.` / `_` / `~`) pass through,
    /// every other byte of the UTF-8 encoding becomes `%XX`. Space encodes
    /// as `%20` (never `+`) and `+` as `%2B`, so the output reads back
    /// identically under both RFC-3986 and WHATWG-form-decoding servers.
    static func encodeComponent(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.utf8.count)
        for byte in s.utf8 {
            if isUnreserved(byte) {
                out.unicodeScalars.append(Unicode.Scalar(byte))
            } else {
                out.append("%")
                out.append(hexDigits[Int(byte >> 4)])
                out.append(hexDigits[Int(byte & 0x0F)])
            }
        }
        return out
    }

    /// Assembles `key=value&…` (no leading `?`) with keys sorted, so the
    /// same parameters always produce the same URL — deterministic output,
    /// mirroring `JSONValue.jsonString`'s sorted object keys. Empty input
    /// yields an empty string.
    static func queryString(_ query: [String: HTTPQueryValue]) -> String {
        query.sorted { $0.key < $1.key }
            .map { encodeComponent($0.key) + "=" + encodeComponent($0.value.text) }
            .joined(separator: "&")
    }

    private static let hexDigits: [Character] = Array("0123456789ABCDEF")

    private static func isUnreserved(_ b: UInt8) -> Bool {
        switch b {
        case UInt8(ascii: "a")...UInt8(ascii: "z"),
             UInt8(ascii: "A")...UInt8(ascii: "Z"),
             UInt8(ascii: "0")...UInt8(ascii: "9"),
             UInt8(ascii: "-"), UInt8(ascii: "."), UInt8(ascii: "_"), UInt8(ascii: "~"):
            return true
        default:
            return false
        }
    }
}
