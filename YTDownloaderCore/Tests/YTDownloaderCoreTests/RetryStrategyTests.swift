import XCTest
@testable import YTDownloaderCore

final class RetryStrategyTests: XCTestCase {
    func testDelayCalculation() {
        let strategy = RetryStrategy(maxAttempts: 10, baseDelay: 5...30, additionalDelayPerAttempt: 60)
        
        let delay1 = strategy.delay(forAttempt: 1)
        XCTAssertGreaterThanOrEqual(delay1, 5)
        XCTAssertLessThanOrEqual(delay1, 30)
        
        let delay2 = strategy.delay(forAttempt: 2)
        XCTAssertGreaterThanOrEqual(delay2, 5 + 60)
        XCTAssertLessThanOrEqual(delay2, 30 + 60)
        
        let delay5 = strategy.delay(forAttempt: 5)
        XCTAssertGreaterThanOrEqual(delay5, 5 + 240)
        XCTAssertLessThanOrEqual(delay5, 30 + 240)
    }
    
    func testShouldRetryTransientErrors() {
        let strategy = RetryStrategy(maxAttempts: 10)
        
        XCTAssertTrue(strategy.shouldRetry(error: .forbidden, attempt: 1))
        XCTAssertTrue(strategy.shouldRetry(error: .tooManyRequests, attempt: 5))
        XCTAssertTrue(strategy.shouldRetry(error: .networkError("test"), attempt: 3))
    }
    
    func testShouldNotRetryNonTransientErrors() {
        let strategy = RetryStrategy(maxAttempts: 10)
        
        XCTAssertFalse(strategy.shouldRetry(error: .invalidURL, attempt: 1))
        XCTAssertFalse(strategy.shouldRetry(error: .noSuitableFormats, attempt: 1))
        XCTAssertFalse(strategy.shouldRetry(error: .ytdlpNotFound, attempt: 1))
    }
    
    func testShouldNotRetryAfterMaxAttempts() {
        let strategy = RetryStrategy(maxAttempts: 3)
        
        XCTAssertTrue(strategy.shouldRetry(error: .forbidden, attempt: 1))
        XCTAssertTrue(strategy.shouldRetry(error: .forbidden, attempt: 2))
        XCTAssertFalse(strategy.shouldRetry(error: .forbidden, attempt: 3))
        XCTAssertFalse(strategy.shouldRetry(error: .forbidden, attempt: 4))
    }
    
    func testRetryStateTracking() {
        var state = RetryState()
        
        XCTAssertEqual(state.attempt, 0)
        XCTAssertNil(state.lastError)
        
        state.recordAttempt(error: .forbidden)
        XCTAssertEqual(state.attempt, 1)
        XCTAssertEqual(state.lastError, .forbidden)
        
        state.recordAttempt(error: .tooManyRequests)
        XCTAssertEqual(state.attempt, 2)
        XCTAssertEqual(state.lastError, .tooManyRequests)
        
        state.reset()
        XCTAssertEqual(state.attempt, 0)
        XCTAssertNil(state.lastError)
    }
}
