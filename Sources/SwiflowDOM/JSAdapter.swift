// Sources/SwiflowDOM/JSAdapter.swift

#if canImport(JavaScriptKit)
import JavaScriptKit
import Swiflow

/// Converts a Swift `PatchPayload` into the `JSObject` shape the JS driver
/// expects: `{ op: String, ...named fields }`. Each field marshals through the
/// single `JSScalar` crossing (see `PatchPayload.Field.toJSValue`), so the
/// primitive→`JSValue` mapping lives in one place rather than being inlined here.
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
        // Every field marshals through the single `JSScalar` crossing.
        switch self {
        case .int(let n):       return JSScalar.int(n).jsValue
        case .string(let s):    return JSScalar.string(s).jsValue
        case .double(let d):    return JSScalar.double(d).jsValue
        case .property(let pv): return pv.jsScalar.jsValue
        }
    }
}

#endif
