// Tests/SwiflowQueryTests/RetryPolicyTests.swift
import Testing
@testable import SwiflowQuery

@Suite("RetryPolicy")
struct RetryPolicyTests {
    @Test func defaultBackoffSequence() {
        let p = RetryPolicy.default
        #expect(p.delay(forAttempt: 0) == .seconds(1))
        #expect(p.delay(forAttempt: 1) == .seconds(2))
        #expect(p.delay(forAttempt: 2) == .seconds(4))
    }
    @Test func backoffCapsAndNeverOverflows() {
        let p = RetryPolicy.default
        #expect(p.delay(forAttempt: 5) == .seconds(30))      // 1·2^5 = 32s → capped at 30s
        #expect(p.delay(forAttempt: 100_000) == .seconds(30))// no Duration overflow/trap
    }
    @Test func noneDisablesRetry() {
        #expect(RetryPolicy.none.maxRetries == 0)
    }
    @Test func hugeMaxDelayNeverOverflows() {
        // A caller-built policy with a near-max maxDelay must cap, never trap,
        // for any attempt count (the guard clamps the result, not the exponent).
        let p = RetryPolicy(maxRetries: 500, baseDelay: .seconds(1), maxDelay: .seconds(Int64.max / 4))
        #expect(p.delay(forAttempt: 500) == .seconds(Int64.max / 4))
    }
}
