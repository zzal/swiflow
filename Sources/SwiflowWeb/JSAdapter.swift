// Sources/SwiflowWeb/JSAdapter.swift

#if canImport(JavaScriptKit)
import JavaScriptKit
import Swiflow

/// Converts a Swift `PatchPayload` into the `JSObject` shape the JS driver
/// expects: `{ op: String, ...named fields }`.
///
/// Field-level mapping rules:
/// - `.int(n)` → JS Number.
/// - `.string(s)` → JS String.
/// - `.property(.string(s))` → JS String.
/// - `.property(.int(n))` → JS Number.
/// - `.property(.double(d))` → JS Number.
/// - `.property(.bool(b))` → JS Boolean.
enum JSAdapter {
    static func toJSValue(_ payload: PatchPayload) -> JSValue {
        let obj = JSObject.global.Object.function!.new()
        obj.op = .string(payload.op)
        for (name, field) in payload.fields {
            obj[name] = field.toJSValue()
        }
        return .object(obj)
    }
}

extension PatchPayload.Field {
    func toJSValue() -> JSValue {
        switch self {
        case .int(let n):
            return .number(Double(n))
        case .string(let s):
            return .string(s)
        case .double(let d):
            return .number(d)
        case .property(let pv):
            switch pv {
            case .string(let s): return .string(s)
            case .int(let n): return .number(Double(n))
            case .double(let d): return .number(d)
            case .bool(let b): return .boolean(b)
            }
        }
    }
}

#endif
