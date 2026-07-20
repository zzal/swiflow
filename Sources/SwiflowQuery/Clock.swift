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
        // arch(wasm32), NOT canImport(JavaScriptKit): JavaScriptKit is an
        // unconditional dependency, so canImport is TRUE on the host too and
        // the JS branch would compile there and trap at JSObject.global the
        // first time a host test constructs a default-clocked QueryClient.
        #if arch(wasm32)
        let ms = JSObject.global.performance.object?.now?().number ?? 0
        return SystemQueryClock.duration(millisecondsSinceOrigin: ms)
        #else
        return ContinuousClock().now - SystemQueryClock.hostOrigin
        #endif
    }

    /// Converts a `performance.now()` reading (milliseconds since navigation
    /// start) into a `Duration`.
    ///
    /// Widens through `Int64`, never `Int`: on wasm32 `Int` is 32-bit, so a bare
    /// `Int(ms)` traps — killing the whole app — once page uptime passes
    /// `Int32.max` ms ≈ 24.85 days, exactly the long-lived dashboard workload the
    /// cache is built for. The host's 64-bit `Int` hides the narrowing, so this
    /// is separated out to be host-testable at the boundary. `Int64(exactly:)`
    /// also absorbs a non-finite reading (which would trap even on the host):
    /// the `?? .max` fallback treats it as maximally stale — a refetch, never a
    /// crash. Extracted (not inlined in `now()`) precisely so these rules can be
    /// pinned by unit tests the browser-only path otherwise can't reach.
    static func duration(millisecondsSinceOrigin ms: Double) -> Duration {
        .milliseconds(Int64(exactly: ms.rounded()) ?? .max)
    }

    #if !arch(wasm32)
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
