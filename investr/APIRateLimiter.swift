import Foundation

// MARK: - API Rate Limiter
final class APIRateLimiter {
    static let shared = APIRateLimiter()
    
    // Wait time between API requests (in seconds)
    private let waitTimeBetweenRequests: TimeInterval = 20
    
    // In-memory tracking of last request times by endpoint
    private var lastRequestTimes: [String: Date] = [:]
    private let lock = NSLock()
    
    private init() {}
    
    func waitForSlot(endpoint: String = "default") async throws {
        let now = Date()
        var timeToWait: TimeInterval = 0
        
        lock.lock()
        if let lastTime = lastRequestTimes[endpoint] {
            let elapsed = now.timeIntervalSince(lastTime)
            if elapsed < waitTimeBetweenRequests {
                timeToWait = waitTimeBetweenRequests - elapsed
            }
        }
        
        // Update the last request time immediately
        lastRequestTimes[endpoint] = now.addingTimeInterval(timeToWait)
        lock.unlock()
        
        if timeToWait > 0 {
            print("APIRateLimiter: Waiting for \(timeToWait) seconds for endpoint \(endpoint)")
            try await Task.sleep(nanoseconds: UInt64(timeToWait * 1_000_000_000))
        }
    }
    
    // For APIs with different rate limits
    func configureEndpoint(name: String, waitTime: TimeInterval) {
        // Could add endpoint-specific configuration
    }
    
    // Reset all rate limiting (for testing or when app settings change)
    func reset() {
        lock.lock()
        lastRequestTimes.removeAll()
        lock.unlock()
    }
} 