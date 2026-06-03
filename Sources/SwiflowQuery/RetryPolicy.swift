// Sources/SwiflowQuery/RetryPolicy.swift

/// How a failed query fetch is retried. A closure-free value (`Sendable` +
/// `Equatable`) so it can live on the `Query` protocol.
public struct RetryPolicy: Sendable, Equatable {
    /// Retries AFTER the initial fetch (total attempts = `maxRetries + 1`).
    public var maxRetries: Int
    /// Delay before the first retry; doubles each retry, capped at `maxDelay`.
    public var baseDelay: Duration
    public var maxDelay: Duration

    public init(maxRetries: Int, baseDelay: Duration, maxDelay: Duration) {
        self.maxRetries = maxRetries
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
    }

    /// No retries.
    public static let none = RetryPolicy(maxRetries: 0, baseDelay: .zero, maxDelay: .zero)
    /// 3 retries at 1s / 2s / 4s, capped at 30s.
    public static let `default` = RetryPolicy(maxRetries: 3, baseDelay: .seconds(1), maxDelay: .seconds(30))

    /// Backoff before retry `n` (0-indexed) = `baseDelay × 2ⁿ`, capped at `maxDelay`.
    /// Clamps the RESULT by doubling, so it never forms an overflowing product.
    func delay(forAttempt n: Int) -> Duration {
        var d = baseDelay
        if d >= maxDelay { return maxDelay }
        for _ in 0..<n {
            d = d * 2
            if d >= maxDelay { return maxDelay }
        }
        return d
    }
}
