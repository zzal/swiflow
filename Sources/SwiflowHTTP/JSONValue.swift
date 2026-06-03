// Sources/SwiflowHTTP/JSONValue.swift
//
// A small, Sendable JSON value used for request bodies. Literal-expressible so
// bodies read naturally inline — `["title": .string(name), "done": false]` —
// and it serializes to a compact JSON string in pure Swift (no Foundation, no
// JSValueEncoder), which is both WASM-safe and unit-testable off-WASM.

/// A JSON value for `HTTP` request bodies.
///
/// Conforms to the `ExpressibleBy*Literal` family, so object/array/string/
/// number/bool/null literals work directly:
///
/// ```swift
/// let body: JSONValue = ["title": .string(title), "done": false, "tags": ["a", "b"]]
/// ```
///
/// Dynamic (non-literal) values are wrapped explicitly — `.string(title)`,
/// `.int(count)` — because Swift only applies literal conversions to literals.
public enum JSONValue: Sendable, Equatable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
}

// MARK: - Literals

extension JSONValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
}
extension JSONValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) { self = .int(value) }
}
extension JSONValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) { self = .double(value) }
}
extension JSONValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) { self = .bool(value) }
}
extension JSONValue: ExpressibleByNilLiteral {
    public init(nilLiteral: ()) { self = .null }
}
extension JSONValue: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
}
extension JSONValue: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        // Last value wins on duplicate keys (rather than trapping) — defensive;
        // JSON object literals shouldn't repeat keys.
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
}

// MARK: - Serialization

public extension JSONValue {
    /// A compact JSON-encoded string. Pure Swift stdlib — no Foundation — so it
    /// builds the body inside the WASM target and is fully unit-testable on the
    /// host. Object keys are emitted in sorted order for deterministic output.
    var jsonString: String {
        switch self {
        case .null:          return "null"
        case .bool(let b):   return b ? "true" : "false"
        case .int(let i):    return String(i)
        case .double(let d): return String(d)
        case .string(let s): return Self.escape(s)
        case .array(let a):
            return "[" + a.map(\.jsonString).joined(separator: ",") + "]"
        case .object(let o):
            let pairs = o.sorted { $0.key < $1.key }
                .map { Self.escape($0.key) + ":" + $0.value.jsonString }
            return "{" + pairs.joined(separator: ",") + "}"
        }
    }

    /// JSON string escaping per RFC 8259, Foundation-free.
    private static func escape(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"":      out += "\\\""
            case "\\":      out += "\\\\"
            case "\n":      out += "\\n"
            case "\r":      out += "\\r"
            case "\t":      out += "\\t"
            case "\u{08}":  out += "\\b"
            case "\u{0C}":  out += "\\f"
            default:
                if scalar.value < 0x20 {
                    let hex = String(scalar.value, radix: 16)
                    out += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        out += "\""
        return out
    }
}
