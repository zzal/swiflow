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
/// Values are either a concrete primitive (Bool/Int/Double/String) — from a
/// non-Optional `@State` or an Optional `.some(payload)` the `@Component`
/// macro unwrapped at the source via `.map { $0 as Any }` — or an
/// `HMRNilSentinel` for Optional `.none`, which the macro normalizes at the
/// source because `Optional<T>.none` stored in `Any` is type-erased and
/// cannot be distinguished by exhaustive `as?` checks here. We never see a
/// raw `Optional<T>.none` — the macro guarantees it. Bool is checked before
/// Int because Swift bridges Bool to NSNumber and `v as? Int` succeeds for
/// Bool values.
@MainActor
func encodeStateMapToJS(_ state: [String: Any]) -> JSValue {
    let obj = JSObject.global.Object.function!.new()
    for (k, v) in state {
        if v is HMRNilSentinel {
            obj[k] = .null
        } else if let b = v as? Bool {
            obj[k] = .boolean(b)
        } else if let s = v as? String {
            obj[k] = .string(s)
        } else if let i = v as? Int {
            obj[k] = .number(Double(i))
        } else if let d = v as? Double {
            obj[k] = .number(d)
        }
        // Other unsupported types — skip (v1 limitation).
    }
    return .object(obj)
}

#endif  // !SWIFLOW_RELEASE

#endif  // canImport(JavaScriptKit)
