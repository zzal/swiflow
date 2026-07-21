// Sources/SwiflowColor/PaletteFailure.swift
//
// Public result/error types for the theme generator. SwiflowColor is native-only
// (CLI + host tooling) — NEVER add it to the wasm SwiflowUI target.
import Foundation

/// One contrast shortfall for a generated token, in one color scheme, with its advisory
/// APCA reading. Returned in `ThemeResult.failures`.
public struct PaletteFailure: Equatable, Sendable, CustomStringConvertible {
    public let token: String
    public let mode: String        // "light" | "dark"
    public let ratio: Double
    public let target: Double
    /// Signed APCA Lc for this token's text/surface pairing (advisory; `abs` is compared).
    public let apcaLc: Double
    /// APCA's recommended Lc for this usage (75 text, 45 non-text). Guidance, never gated.
    public let apcaTarget: Double

    public init(token: String, mode: String, ratio: Double, target: Double,
                apcaLc: Double, apcaTarget: Double) {
        self.token = token; self.mode = mode; self.ratio = ratio; self.target = target
        self.apcaLc = apcaLc; self.apcaTarget = apcaTarget
    }

    public var description: String {
        let wcag = String(format: "%@ (%@): %.2f:1 < %.1f:1 required", token, mode, ratio, target)
        let usage = apcaTarget >= 75 ? "text" : "non-text"
        let apca = String(format: " — APCA Lc %.0f (suggests ≥ %.0f for %@)",
                          abs(apcaLc), apcaTarget, usage)
        return wcag + apca
    }
}

/// Errors thrown by the theme generator. Contrast shortfalls are NOT errors — they are
/// returned in `ThemeResult.failures`. Only malformed input throws.
public enum ThemeError: Error, CustomStringConvertible {
    case invalidHex(String)
    /// A value that looked like `oklch(…)` but didn't parse as `oklch(L C H)`.
    case invalidColor(String)
    public var description: String {
        switch self {
        case .invalidHex(let s): return "invalid theme color hex: \(s) (expected #rgb or #rrggbb)"
        case .invalidColor(let s): return "invalid theme color: \(s) (expected oklch(L C H) or #rgb/#rrggbb)"
        }
    }
}
