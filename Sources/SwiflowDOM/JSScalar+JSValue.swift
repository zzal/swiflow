// Sources/SwiflowDOM/JSScalar+JSValue.swift

#if canImport(JavaScriptKit)
import JavaScriptKit
import Swiflow

/// The single `JSScalar` ↔ `JSValue` crossing. Every place Swift hands a scalar
/// to (or takes one from) the JS driver — HMR snapshot encode/decode and DOM
/// `PropertyValue` marshalling — routes through here, instead of re-deriving the
/// primitive mapping per site. The subtle Swift-side rules live in core
/// `JSScalar` (host-tested); this layer is the thin JS boundary.
extension JSScalar {
    /// Classifies a JS value from the driver. A JS number becomes `.int` when it
    /// is integral, finite, and fits `Int` (so `@State var count: Int` and
    /// `select.selectedIndex` round-trip without loss), otherwise `.double`.
    /// Returns nil for a JS type outside the scalar set (object/function/
    /// undefined), which callers skip.
    ///
    /// `.boolean`/`.string`/`.number` are mutually exclusive JS types (unlike
    /// Swift, where `Bool` bridges to `NSNumber`), so branch order here is not
    /// load-bearing — the fragile ordering rule is on the `stateValue` side.
    package init?(jsValue value: JSValue) {
        if let b = value.boolean {
            self = .bool(b)
        } else if let s = value.string {
            self = .string(s)
        } else if let n = value.number {
            if n.truncatingRemainder(dividingBy: 1) == 0 && n.isFinite
                && n >= Double(Int.min) && n <= Double(Int.max) {
                self = .int(Int(n))
            } else {
                self = .double(n)
            }
        } else if case .null = value {
            self = .null
        } else {
            return nil
        }
    }

    /// This scalar as a `JSValue` for the driver. Both `.int` and `.double`
    /// become a JS `Number` (JS has a single number type).
    package var jsValue: JSValue {
        switch self {
        case .string(let s): return .string(s)
        case .int(let i):    return .number(Double(i))
        case .double(let d): return .number(d)
        case .bool(let b):   return .boolean(b)
        case .null:          return .null
        }
    }
}
#endif
