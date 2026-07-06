// Sources/Swiflow/JSScalar.swift

/// The closed set of scalar values that cross the Swift↔JS boundary.
///
/// It is the single taxonomy for the two crossings that used to re-derive
/// "which JS primitive is this" independently — `@State` HMR snapshots and DOM
/// `PropertyValue` marshalling. The SUBTLE classification rules (Bool-before-Int,
/// `HMRNilSentinel`↔null) live in THIS host-testable core layer, so a coercion
/// slip is a unit-test failure rather than a silent HMR-state corruption found
/// by hand (the "Blocker 2/3" class the HMR round-trip tests were written for).
///
/// The `JSValue` crossing itself (`init?(jsValue:)` / `jsValue`) is a SwiflowDOM
/// extension, so this core type stays free of JavaScriptKit.
package enum JSScalar: Equatable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
}

extension JSScalar {
    /// Classifies a `@State` snapshot value — as produced by the `@Component`
    /// macro: a concrete `Bool`/`Int`/`Double`/`String`, or `HMRNilSentinel`
    /// for an Optional `.none` the macro normalized at the source. Returns nil
    /// for an unsupported type (a v1 limitation the encoder skips).
    ///
    /// **Order matters:** `HMRNilSentinel` first, then `Bool` BEFORE `Int` —
    /// Swift bridges `Bool` to `NSNumber`, so `(true as Any) as? Int` succeeds
    /// and would misclassify a boolean as `1`.
    package init?(stateValue: Any) {
        if stateValue is HMRNilSentinel {
            self = .null
        } else if let b = stateValue as? Bool {
            self = .bool(b)
        } else if let s = stateValue as? String {
            self = .string(s)
        } else if let i = stateValue as? Int {
            self = .int(i)
        } else if let d = stateValue as? Double {
            self = .double(d)
        } else {
            return nil
        }
    }

    /// The Swift value this scalar restores to on the `@State` restore path.
    /// `.null` becomes `HMRNilSentinel`, which the macro-emitted restore closure
    /// routes to `restoreNil` (writing `Optional.none` for Optional fields).
    package var stateValue: Any {
        switch self {
        case .string(let s): return s
        case .int(let i):    return i
        case .double(let d): return d
        case .bool(let b):   return b
        case .null:          return HMRNilSentinel()
        }
    }
}

extension PropertyValue {
    /// The scalar this DOM property marshals to. `PropertyValue` never carries
    /// null — that domain belongs to attributes / `removeProperty`.
    package var jsScalar: JSScalar {
        switch self {
        case .string(let s): return .string(s)
        case .int(let i):    return .int(i)
        case .double(let d): return .double(d)
        case .bool(let b):   return .bool(b)
        }
    }
}
