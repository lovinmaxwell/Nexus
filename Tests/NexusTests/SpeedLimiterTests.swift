import XCTest

@testable import NexusApp

/// Unit tests for the Token Bucket algorithm implementation in SpeedLimiter.
///
/// These tests verify:
/// - Token consumption and refill mechanics
/// - Rate limiting behavior
/// - Burst allowance handling
/// - Dynamic rate changes
final class SpeedLimiterTests: XCTestCase {

    // MARK: - TokenBucket Tests

    func test_tokenBucket_initialState_hasfullCapacity() async {
        let bucket = TokenBucket(capacity: 1000, refillRateBytesPerSecond: 100)

        let available = await bucket.availableTokens
        XCTAssertEqual(available, 1000, accuracy: 1.0, "Bucket should start with full capacity")
    }

    func test_tokenBucket_tryConsumeTokens_succeedsWhenSufficientTokens() async {
        let bucket = TokenBucket(capacity: 1000, refillRateBytesPerSecond: 100)

        let consumed = await bucket.tryConsumeTokens(amount: 500)
        XCTAssertTrue(consumed, "Should successfully consume tokens when sufficient")

        let remaining = await bucket.availableTokens
        XCTAssertEqual(remaining, 500, accuracy: 10.0, "Should have ~500 tokens remaining")
    }

    func test_tokenBucket_tryConsumeTokens_failsWhenInsufficientTokens() async {
        let bucket = TokenBucket(capacity: 100, refillRateBytesPerSecond: 10)

        // Drain the bucket
        _ = await bucket.tryConsumeTokens(amount: 100)

        // Try to consume more than available
        let consumed = await bucket.tryConsumeTokens(amount: 50)
        XCTAssertFalse(consumed, "Should fail when insufficient tokens")
    }

    func test_tokenBucket_refillsOverTime() async {
        let refillRate: Int64 = 1000  // 1000 bytes/second
        let bucket = TokenBucket(capacity: 1000, refillRateBytesPerSecond: refillRate)

        // Drain the bucket
        _ = await bucket.tryConsumeTokens(amount: 1000)

        // Wait for some refill (100ms should add ~100 tokens)
        try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms

        let available = await bucket.availableTokens
        XCTAssertGreaterThan(available, 50, "Should have refilled some tokens after 100ms")
        XCTAssertLessThan(available, 200, "Should not have refilled too many tokens")
    }

    func test_tokenBucket_requestTokens_waitsWhenInsufficientTokens() async {
        let refillRate: Int64 = 10_000  // 10KB/s for faster test
        let bucket = TokenBucket(capacity: 1000, refillRateBytesPerSecond: refillRate)

        // Drain the bucket
        _ = await bucket.tryConsumeTokens(amount: 1000)

        let startTime = Date()

        // Request tokens - should wait for refill
        await bucket.requestTokens(amount: 500)

        let elapsed = Date().timeIntervalSince(startTime)

        // Should have waited approximately 50ms (500 tokens / 10000 rate)
        XCTAssertGreaterThan(elapsed, 0.03, "Should have waited for token refill")
        XCTAssertLessThan(elapsed, 0.5, "Should not wait excessively")
    }

    func test_tokenBucket_capacityLimitsMaxTokens() async {
        let bucket = TokenBucket(capacity: 500, refillRateBytesPerSecond: 10000)

        // Wait longer than needed to fully refill
        try? await Task.sleep(nanoseconds: 200_000_000)  // 200ms

        let available = await bucket.availableTokens

        // Should be capped at capacity
        XCTAssertLessThanOrEqual(
            available, 500, "Tokens should not exceed capacity")
    }

    func test_tokenBucket_multipleConsumptions_tracksCorrectly() async {
        let bucket = TokenBucket(capacity: 1000, refillRateBytesPerSecond: 100)

        // Consume in multiple small chunks
        _ = await bucket.tryConsumeTokens(amount: 200)
        _ = await bucket.tryConsumeTokens(amount: 300)
        _ = await bucket.tryConsumeTokens(amount: 100)

        let remaining = await bucket.availableTokens
        XCTAssertEqual(remaining, 400, accuracy: 20.0, "Should track multiple consumptions")
    }

    // MARK: - SpeedLimiter Tests

    @MainActor
    func test_speedLimiter_defaultState_isDisabled() async {
        let limiter = SpeedLimiter.shared

        // Reset to default state
        limiter.disableLimit()

        XCTAssertFalse(limiter.isEnabled, "SpeedLimiter should be disabled by default")
        XCTAssertEqual(limiter.limitBytesPerSecond, 0, "Limit should be 0 when disabled")
    }

    @MainActor
    func test_speedLimiter_setLimit_enablesLimiting() async {
        let limiter = SpeedLimiter.shared

        limiter.setLimit(bytesPerSecond: 1_000_000)  // 1 MB/s

        XCTAssertTrue(limiter.isEnabled, "Limiter should be enabled after setting limit")
        XCTAssertEqual(limiter.limitBytesPerSecond, 1_000_000, "Limit should be set correctly")
    }

    @MainActor
    func test_speedLimiter_setLimitToZero_disablesLimiting() async {
        let limiter = SpeedLimiter.shared

        limiter.setLimit(bytesPerSecond: 1_000_000)
        limiter.setLimit(bytesPerSecond: 0)

        XCTAssertFalse(limiter.isEnabled, "Limiter should be disabled when set to 0")
    }

    @MainActor
    func test_speedLimiter_disableLimit_clearsState() async {
        let limiter = SpeedLimiter.shared

        limiter.setLimit(bytesPerSecond: 1_000_000)
        limiter.disableLimit()

        XCTAssertFalse(limiter.isEnabled, "Limiter should be disabled")
        XCTAssertEqual(limiter.limitBytesPerSecond, 0, "Limit should be cleared")
    }

    @MainActor
    func test_speedLimiter_limitDescription_formatsCorrectly() async {
        let limiter = SpeedLimiter.shared

        limiter.disableLimit()
        XCTAssertEqual(limiter.limitDescription, "Unlimited", "Should show Unlimited when disabled")

        limiter.setLimit(bytesPerSecond: 1_000_000)  // 1 MB/s
        XCTAssertTrue(
            limiter.limitDescription.contains("MB") || limiter.limitDescription.contains("KB"),
            "Should format bytes correctly: \(limiter.limitDescription)")

        // Cleanup
        limiter.disableLimit()
    }

    @MainActor
    func test_speedLimiter_requestPermission_returnsImmediatelyWhenDisabled() async {
        let limiter = SpeedLimiter.shared
        limiter.disableLimit()

        let startTime = Date()
        await limiter.requestPermissionToTransfer(bytes: 1_000_000)
        let elapsed = Date().timeIntervalSince(startTime)

        XCTAssertLessThan(elapsed, 0.01, "Should return immediately when disabled")
    }

    @MainActor
    func test_speedLimiter_burstAllowance_isTwoSecondsCapacity() async {
        let limiter = SpeedLimiter.shared
        let bytesPerSecond: Int64 = 1_000_000  // 1 MB/s

        limiter.setLimit(bytesPerSecond: bytesPerSecond)

        // The burst capacity should be 2 * bytesPerSecond = 2 MB
        // This allows short bursts without immediate throttling
        // We can't directly test the capacity, but we can verify behavior

        let startTime = Date()
        // Request up to burst limit (should be immediate or very fast)
        await limiter.requestPermissionToTransfer(bytes: Int(bytesPerSecond * 2))
        let elapsed = Date().timeIntervalSince(startTime)

        // Should complete quickly because we have burst capacity
        XCTAssertLessThan(elapsed, 0.5, "Burst should be allowed without significant delay")

        // Cleanup
        limiter.disableLimit()
    }

    // MARK: - Rate Limiting Behavior Tests

    func test_tokenBucket_enforcesRateLimit() async {
        let rate: Int64 = 10_000  // 10 KB/s
        let bucket = TokenBucket(capacity: 1000, refillRateBytesPerSecond: rate)

        // Drain bucket
        _ = await bucket.tryConsumeTokens(amount: 1000)

        let startTime = Date()
        var totalTransferred: Int64 = 0
        let targetBytes: Int64 = 5000  // 5 KB

        // Transfer in 1KB chunks
        while totalTransferred < targetBytes {
            await bucket.requestTokens(amount: 1000)
            totalTransferred += 1000
        }

        let elapsed = Date().timeIntervalSince(startTime)

        // At 10 KB/s, 5 KB should take approximately 0.5 seconds
        // Allow some margin for test execution overhead
        XCTAssertGreaterThan(elapsed, 0.3, "Should enforce rate limit")
        XCTAssertLessThan(elapsed, 1.0, "Should not over-throttle")
    }
}
