import XCTest
@testable import YTDownloaderCore

final class RetryStrategyTests: XCTestCase {
    func testDelayCalculation() {
        let strategy = RetryStrategy(maxAttempts: 10, baseDelay: 5...30, additionalDelayPerAttempt: 60)
        
        // Formula: random(5...30) + 60*(n-1) where n is the attempt number
        
        // Attempt 1: random(5...30) + 60*0 = random(5...30)
        let delay1 = strategy.delay(forAttempt: 1)
        XCTAssertGreaterThanOrEqual(delay1, 5)
        XCTAssertLessThanOrEqual(delay1, 30)
        
        // Attempt 2: random(5...30) + 60*1 = random(65...90)
        let delay2 = strategy.delay(forAttempt: 2)
        XCTAssertGreaterThanOrEqual(delay2, 65)
        XCTAssertLessThanOrEqual(delay2, 90)
        
        // Attempt 3: random(5...30) + 60*2 = random(125...150)
        let delay3 = strategy.delay(forAttempt: 3)
        XCTAssertGreaterThanOrEqual(delay3, 125)
        XCTAssertLessThanOrEqual(delay3, 150)
        
        // Attempt 5: random(5...30) + 60*4 = random(245...270)
        let delay5 = strategy.delay(forAttempt: 5)
        XCTAssertGreaterThanOrEqual(delay5, 245)
        XCTAssertLessThanOrEqual(delay5, 270)
        
        // Attempt 10: random(5...30) + 60*9 = random(545...570)
        let delay10 = strategy.delay(forAttempt: 10)
        XCTAssertGreaterThanOrEqual(delay10, 545)
        XCTAssertLessThanOrEqual(delay10, 570)
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
