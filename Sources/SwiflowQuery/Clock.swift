// Sources/SwiflowQuery/Clock.swift

#if canImport(JavaScriptKit)
import JavaScriptKit
#endif

/// A monotonic time source. `now()` returns elapsed time since an arbitrary
/// fixed origin, so freshness comparisons can never be corrupted by a
/// wall-clock adjustment.
public protocol QueryClock {
    func now() -> Duration
}

/// Production clock. In the browser it reads `performance.now()` (monotonic,
/// millisecond resolution). On the host it uses `ContinuousClock` (monotonic).
/// Deterministic tests inject `ManualClock` instead; this type is smoke-tested
/// in the browser, not unit-tested.
public struct SystemQueryClock: QueryClock {
    public init() {}

    public func now() -> Duration {
        #if canImport(JavaScriptKit)
        let ms = JSObject.global.performance.object?.now?().number ?? 0
        return .milliseconds(Int(ms))
        #else
        return ContinuousClock().now - SystemQueryClock.hostOrigin
        #endif
    }

    #if !canImport(JavaScriptKit)
    private static let hostOrigin = ContinuousClock().now
    #endif
}

/// A test clock advanced explicitly. `@MainActor` use only (the client mutates
/// and reads it on the main actor).
public final class ManualClock: QueryClock {
    private var current: Duration
    public init(_ start: Duration = .zero) { self.current = start }
    public func now() -> Duration { current }
    public func advance(by delta: Duration) { current = current + delta }
}
