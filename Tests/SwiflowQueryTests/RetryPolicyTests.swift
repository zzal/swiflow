// Tests/SwiflowQueryTests/RetryPolicyTests.swift
import Testing
@testable import SwiflowQuery

@Suite("RetryPolicy")
struct RetryPolicyTests {
    @Test("The default policy backs off exponentially: 1s, 2s, 4s") func defaultBackoffSequence() {
        let p = RetryPolicy.default
        #expect(p.delay(forAttempt: 0) == .seconds(1))
        #expect(p.delay(forAttempt: 1) == .seconds(2))
        #expect(p.delay(forAttempt: 2) == .seconds(4))
    }
    @Test("Backoff caps at maxDelay and never overflows for huge attempt counts") func backoffCapsAndNeverOverflows() {
        let p = RetryPolicy.default
        #expect(p.delay(forAttempt: 5) == .seconds(30))      // 1·2^5 = 32s → capped at 30s
        #expect(p.delay(forAttempt: 100_000) == .seconds(30))// no Duration overflow/trap
    }
    @Test(".none disables retries via a zero maxRetries") func noneDisablesRetry() {
        #expect(RetryPolicy.none.maxRetries == 0)
    }
    @Test("A near-max maxDelay clamps the delay without trapping at high attempt counts") func hugeMaxDelayNeverOverflows() {
        // A caller-built policy with a near-max maxDelay must cap, never trap,
        // for any attempt count (the guard clamps the result, not the exponent).
        let p = RetryPolicy(maxRetries: 500, baseDelay: .seconds(1), maxDelay: .seconds(Int64.max / 4))
        #expect(p.delay(forAttempt: 500) == .seconds(Int64.max / 4))
    }

    @Test("the defaulted-param init gives the standard backoff, just a different count") func defaultedParamInit() {
        let p = RetryPolicy(maxRetries: 5)
        #expect(p.maxRetries == 5)
        #expect(p.baseDelay == RetryPolicy.default.baseDelay)   // standard 1s doubling…
        #expect(p.maxDelay == RetryPolicy.default.maxDelay)     // …capped at 30s
        #expect(p.delay(forAttempt: 2) == .seconds(4))
    }

    @Test(".retries(n) copies the policy with a new count, keeping the backoff") func retriesFluentCopy() {
        let custom = RetryPolicy(maxRetries: 3, baseDelay: .milliseconds(250), maxDelay: .seconds(5))
        let widened = custom.retries(10)
        #expect(widened.maxRetries == 10)
        #expect(widened.baseDelay == .milliseconds(250))   // backoff preserved
        #expect(widened.maxDelay == .seconds(5))
        // The 90% case reads fluently off .default:
        #expect(RetryPolicy.default.retries(5).maxRetries == 5)
        #expect(RetryPolicy.default.retries(5).baseDelay == .seconds(1))
    }
}
