// Sources/SwiflowQuery/RetryPolicy.swift

/// How a failed query fetch is retried. A closure-free value (`Sendable` +
/// `Equatable`) so it can live on the `Query` protocol.
public struct RetryPolicy: Sendable, Equatable {
    /// Retries AFTER the initial fetch (total attempts = `maxRetries + 1`).
    public var maxRetries: Int
    /// Delay before the first retry; doubles each retry, capped at `maxDelay`.
    public var baseDelay: Duration
    public var maxDelay: Duration

    /// `baseDelay`/`maxDelay` default to the standard backoff (1s doubling,
    /// capped at 30s), so the common "same backoff, different count" case is
    /// just `RetryPolicy(maxRetries: 5)`.
    public init(maxRetries: Int, baseDelay: Duration = .seconds(1), maxDelay: Duration = .seconds(30)) {
        self.maxRetries = maxRetries
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
    }

    /// No retries.
    public static let none = RetryPolicy(maxRetries: 0, baseDelay: .zero, maxDelay: .zero)
    /// 3 retries at 1s / 2s / 4s, capped at 30s.
    public static let `default` = RetryPolicy(maxRetries: 3, baseDelay: .seconds(1), maxDelay: .seconds(30))

    /// A copy with a different retry count, keeping this policy's backoff —
    /// the fluent form of the 90% case: `.default.retries(5)`.
    public func retries(_ n: Int) -> RetryPolicy {
        RetryPolicy(maxRetries: n, baseDelay: baseDelay, maxDelay: maxDelay)
    }

    /// Backoff before retry `n` (0-indexed) = `baseDelay × 2ⁿ`, capped at `maxDelay`.
    /// Clamps the RESULT by doubling, so it never forms an overflowing product.
    func delay(forAttempt n: Int) -> Duration {
        var d = baseDelay
        for _ in 0..<n {
            // Check BEFORE doubling so the product can never overflow `Duration`:
            // if the next double would reach the cap, return the cap now.
            if d >= maxDelay / 2 { return maxDelay }
            d = d * 2
        }
        return min(d, maxDelay)
    }
}
