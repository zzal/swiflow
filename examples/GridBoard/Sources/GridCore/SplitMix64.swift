// Sources/GridCore/SplitMix64.swift
//
// Deterministic PRNG for the synthetic dataset. SplitMix64: tiny, fast,
// statistically fine for demo data, and — critically — identical output
// on host and wasm32 because everything is explicit UInt64 (wasm32's
// native Int is 32-bit; bare-Int mixing would differ or trap).
public struct SplitMix64: Sendable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in [0, 1) with 53 bits of mantissa.
    public mutating func unit() -> Double {
        Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    public mutating func range(_ lo: Double, _ hi: Double) -> Double {
        lo + (hi - lo) * unit()
    }
}
