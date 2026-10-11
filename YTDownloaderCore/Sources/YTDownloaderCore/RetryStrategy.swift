import Foundation

public struct RetryStrategy {
    public let maxAttempts: Int
    public let baseDelay: ClosedRange<TimeInterval>
    public let additionalDelayPerAttempt: TimeInterval
    
    public init(maxAttempts: Int = 10, baseDelay: ClosedRange<TimeInterval> = 5...30, additionalDelayPerAttempt: TimeInterval = 60) {
        self.maxAttempts = maxAttempts
        self.baseDelay = baseDelay
        self.additionalDelayPerAttempt = additionalDelayPerAttempt
    }
    
    /// Calculate delay for a given attempt number (1-indexed)
    public func delay(forAttempt attempt: Int) -> TimeInterval {
        let baseRandomDelay = TimeInterval.random(in: baseDelay)
        let additionalDelay = TimeInterval(attempt - 1) * additionalDelayPerAttempt
        return baseRandomDelay + additionalDelay
    }
    
    /// Determine if an error should be retried
    public func shouldRetry(error: DownloadError, attempt: Int) -> Bool {
        guard attempt < maxAttempts else {
            return false
        }
        
        return error.isTransient
    }
}

public struct RetryState {
    public var attempt: Int = 0
    public var lastError: DownloadError?
    
    public init() {}
    
    public mutating func recordAttempt(error: DownloadError?) {
        attempt += 1
        lastError = error
    }
    
    public mutating func reset() {
        attempt = 0
        lastError = nil
    }
}
