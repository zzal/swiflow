// Sources/SwiflowDOM/JSStateEncoding.swift
//
// Shared encoder for `[String: Any]` state snapshots (as produced by
// `MountNode`/`HMRWalker` state dumps) into a JS object. Used by both the
// HMR snapshot exporter (`HMRBridge.encodeToJS`) and the dev inspection API
// (`DevAPI.state(path)`) — both dev-only, so this lives under the same
// `!SWIFLOW_RELEASE` gate they do.

#if canImport(JavaScriptKit)
import JavaScriptKit
import Swiflow

#if !SWIFLOW_RELEASE

/// Encodes a component's `[String: Any]` state snapshot into a JS object.
///
/// Each value is either a concrete primitive (Bool/Int/Double/String) — from a
/// non-Optional `@State` or an Optional `.some(payload)` the `@Component` macro
/// unwrapped at the source — or an `HMRNilSentinel` for Optional `.none`, which
/// the macro normalizes at the source (a raw `Optional<T>.none` in `Any` is
/// type-erased and can't be distinguished by `as?`). Classification, including
/// the Bool-before-Int ordering, lives in `JSScalar(stateValue:)`; unsupported
/// types classify as nil and are skipped (v1 limitation).
@MainActor
func encodeStateMapToJS(_ state: [String: Any]) -> JSValue {
    let obj = JSObject.global.Object.function!.new()
    for (k, v) in state {
        if let scalar = JSScalar(stateValue: v) {
            obj[k] = scalar.jsValue
        }
    }
    return .object(obj)
}

#endif  // !SWIFLOW_RELEASE

#endif  // canImport(JavaScriptKit)
