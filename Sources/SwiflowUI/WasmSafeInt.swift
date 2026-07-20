// Sources/SwiflowUI/WasmSafeInt.swift
//
// One gate for every Double→Int crossing in SwiflowUI. On wasm32 `Int` is
// 32-bit, so `Int(_:)` on a Double outside signed 32-bit range — or NaN/±∞ —
// TRAPS at runtime. Host `Int` is 64-bit and hides it, so a value like an
// epoch-ms slider bound or a multi-billion-row scroll offset passes every
// host test and then kills the release browser. `cssPixelInt` and
// `formatControlNumber` both guard this class; they funnel through
// `WasmSafeInt` here so the trap can't sneak back in via a new call site with
// its own hand-rolled bound.
import Swiflow

enum WasmSafeInt {
    /// Signed 32-bit range, as `Double` bounds. `Int32.max`/`.min` are exactly
    /// representable in `Double`, so these comparisons are exact.
    static let min = -2_147_483_648.0
    static let max = 2_147_483_647.0

    /// The value as `Int` iff it is finite and lands within signed 32-bit
    /// range; else `nil`. The range comparison also rejects NaN (all
    /// comparisons with NaN are false) and ±∞, so the `Int(_:)` below is
    /// always trap-free — on wasm32 as well as the host.
    static func exact(_ value: Double) -> Int? {
        guard value >= min, value <= max else { return nil }
        return Int(value)
    }

    /// Clamp a non-negative pixel quantity to a trap-free `Int`. NaN and
    /// values below 0 collapse to 0; values past the 32-bit ceiling clamp to
    /// just under it (CSS lengths beyond ~2^31 px are meaningless — browsers
    /// cap element sizes far lower — so clamping identically on EVERY platform
    /// keeps host tests honest about wasm behavior). `+∞` clamps naturally.
    static func pixelClamp(_ value: Double) -> Int {
        guard !value.isNaN else { return 0 }
        return Int(Swift.max(0, Swift.min(value, 2_147_483_000)))
    }
}
