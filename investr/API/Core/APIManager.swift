import Foundation

// MARK: - API Provider Protocol
protocol APIProvider {
    var name: String { get }
    var rateLimitPerMinute: Int { get }
    var apiKeyRequired: Bool { get }
    func fetchCryptoPriceData(symbol: String) async throws -> PriceData
    func fetchETFPriceData(symbol: String) async throws -> PriceData
    func hasValidCredentials() -> Bool
}

// MARK: - API Response Cache
final class APIResponseCache {
    static let shared = APIResponseCache()
    
    private let fileManager = FileManager.default
    private let cacheFolder = "apiCache"
    private var cachePath: URL {
        let paths = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent(cacheFolder)
    }
    
    // In-memory cache
    private var memoryCache: [String: (data: Data, timestamp: Date)] = [:]
    private let memoryCacheLock = NSLock()
    
    // Cache durations
    let cryptoCacheDuration: TimeInterval = 10 * 60 // 10 minutes
    let etfCacheDuration: TimeInterval = 20 * 60 // 20 minutes
    
    init() {
        createCacheDirectoryIfNeeded()
    }
    
    private func createCacheDirectoryIfNeeded() {
        if !fileManager.fileExists(atPath: cachePath.path) {
            do {
                try fileManager.createDirectory(at: cachePath, withIntermediateDirectories: true)
            } catch {
                print("Error creating cache directory: \(error)")
            }
        }
    }
    
    // Store data in both memory and disk cache
    func cacheData(_ data: Data, forKey key: String, type: String) {
        let now = Date()
        
        // Update memory cache
        memoryCacheLock.lock()
        memoryCache[key] = (data, now)
        memoryCacheLock.unlock()
        
        // Update disk cache
        let cacheFile = cachePath.appendingPathComponent("\(type)_\(key).cache")
        do {
            let cacheDict: [String: Any] = [
                "data": data,
                "timestamp": now.timeIntervalSince1970
            ]
            let cacheData = try NSKeyedArchiver.archivedData(withRootObject: cacheDict, requiringSecureCoding: false)
            try cacheData.write(to: cacheFile)
        } catch {
            print("Error writing to cache: \(error)")
        }
    }
    
    // Try to get data from cache
    func getCachedData(forKey key: String, type: String, maxAge: TimeInterval) -> Data? {
        let now = Date()
        
        // Check memory cache first
        memoryCacheLock.lock()
        if let cached = memoryCache[key], now.timeIntervalSince(cached.timestamp) < maxAge {
            memoryCacheLock.unlock()
            return cached.data
        }
        memoryCacheLock.unlock()
        
        // Check disk cache
        let cacheFile = cachePath.appendingPathComponent("\(type)_\(key).cache")
        if fileManager.fileExists(atPath: cacheFile.path) {
            do {
                let cacheData = try Data(contentsOf: cacheFile)
                if let cacheDict = try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(cacheData) as? [String: Any],
                   let timestamp = cacheDict["timestamp"] as? TimeInterval,
                   let data = cacheDict["data"] as? Data {
                    
                    let cacheDate = Date(timeIntervalSince1970: timestamp)
                    if now.timeIntervalSince(cacheDate) < maxAge {
                        // Update memory cache with disk data
                        memoryCacheLock.lock()
                        memoryCache[key] = (data, cacheDate)
                        memoryCacheLock.unlock()
                        return data
                    }
                }
            } catch {
                print("Error reading from cache: \(error)")
            }
        }
        
        return nil
    }
    
    // Clear expired cache entries
    func clearExpiredCache() {
        let now = Date()
        
        // Clear memory cache
        memoryCacheLock.lock()
        let keysToRemove = memoryCache.filter { now.timeIntervalSince($0.value.timestamp) > max(cryptoCacheDuration, etfCacheDuration) }.map { $0.key }
        for key in keysToRemove {
            memoryCache.removeValue(forKey: key)
        }
        memoryCacheLock.unlock()
        
        // Clear disk cache
        do {
            let cacheFiles = try fileManager.contentsOfDirectory(at: cachePath, includingPropertiesForKeys: [.contentModificationDateKey], options: [])
            
            for fileURL in cacheFiles {
                if let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
                   let modificationDate = attributes[.modificationDate] as? Date,
                   now.timeIntervalSince(modificationDate) > max(cryptoCacheDuration, etfCacheDuration) * 2 {
                    try? fileManager.removeItem(at: fileURL)
                }
            }
        } catch {
            print("Error clearing cache: \(error)")
        }
    }
}

// MARK: - Advanced API Rate Limiter
final class AdvancedAPIRateLimiter {
    static let shared = AdvancedAPIRateLimiter()
    
    // Configuration for each endpoint
    private struct EndpointConfig {
        let requestsPerMinute: Int
        var lastRequestTimes: [Date] = []
    }
    
    private var endpoints: [String: EndpointConfig] = [:]
    private let lock = NSLock()
    
    private init() {
        // Set up default endpoints with updated provider names
        configureEndpoint(name: "CoinGecko", requestsPerMinute: 50)
        configureEndpoint(name: "Financial Modeling Prep", requestsPerMinute: 300)
        configureEndpoint(name: "CryptoCompare", requestsPerMinute: 100)
        configureEndpoint(name: "Alpha Vantage", requestsPerMinute: 5)
        configureEndpoint(name: "CoinAPI", requestsPerMinute: 100)
        configureEndpoint(name: "TwelveData", requestsPerMinute: 8)
    }
    
    func configureEndpoint(name: String, requestsPerMinute: Int) {
        lock.lock()
        endpoints[name] = EndpointConfig(requestsPerMinute: requestsPerMinute)
        lock.unlock()
    }
    
    func waitForSlot(endpoint: String) async throws {
        let now = Date()
        var timeToWait: TimeInterval = 0
        
        lock.lock()
        
        // Create endpoint config if it doesn't exist
        if endpoints[endpoint] == nil {
            endpoints[endpoint] = EndpointConfig(requestsPerMinute: 50) // Default rate limit
        }
        
        guard var config = endpoints[endpoint] else {
            lock.unlock()
            return
        }
        
        // Clean up old timestamps (older than 60 seconds)
        config.lastRequestTimes = config.lastRequestTimes.filter { now.timeIntervalSince($0) < 60 }
        
        // Calculate wait time if we're at the limit
        if config.lastRequestTimes.count >= config.requestsPerMinute {
            // Sort timestamps to get the oldest one
            let sortedTimes = config.lastRequestTimes.sorted()
            if let oldestTime = sortedTimes.first {
                // Calculate when the oldest timestamp will "expire" (60 seconds after it was recorded)
                let expiryTime = oldestTime.addingTimeInterval(60)
                timeToWait = expiryTime.timeIntervalSince(now)
                
                if timeToWait <= 0 {
                    timeToWait = 0
                }
            }
        }
        
        // Add the current request time (adjusted for any wait)
        config.lastRequestTimes.append(now.addingTimeInterval(timeToWait))
        endpoints[endpoint] = config
        
        lock.unlock()
        
        if timeToWait > 0 {
            print("APIRateLimiter: Waiting for \(timeToWait) seconds for endpoint \(endpoint)")
            try await Task.sleep(nanoseconds: UInt64(timeToWait * 1_000_000_000))
        }
    }
    
    // Reset rate limiting for an endpoint
    func resetEndpoint(_ endpoint: String) {
        lock.lock()
        if var config = endpoints[endpoint] {
            config.lastRequestTimes.removeAll()
            endpoints[endpoint] = config
        }
        lock.unlock()
    }
}

// MARK: - API Manager
final class APIManager {
    static let shared = APIManager()
    
    // Available API providers
    private var cryptoProviders: [APIProvider] = []
    private var etfProviders: [APIProvider] = []
    private let providerLock = NSLock()
    
    private init() {
        // Register providers in priority order
        registerProviders()
        
        // Schedule cache cleanup
        scheduleCacheCleanup()
    }
    
    private func registerProviders() {
        // Register crypto providers in priority order
        cryptoProviders = [
            CryptoCompareProvider(),
            CoinGeckoProvider(),
            CoinAPIProvider(),
            // Add more providers as needed
        ]
        
        // Register ETF/stock providers in priority order
        etfProviders = [
            FinancialModelingPrepProvider(),
            AlphaVantageProvider(),
            TwelveDataProvider(),
            // Add more providers as needed
        ]
    }
    
    private func scheduleCacheCleanup() {
        Task {
            while true {
                try? await Task.sleep(nanoseconds: UInt64(30 * 60 * 1_000_000_000)) // 30 minutes
                APIResponseCache.shared.clearExpiredCache()
            }
        }
    }
    
    // Get list of available crypto providers
    var availableCryptoProviders: [APIProvider] {
        providerLock.lock()
        defer { providerLock.unlock() }
        return cryptoProviders.filter { $0.hasValidCredentials() }
    }
    
    // Get list of available ETF providers
    var availableETFProviders: [APIProvider] {
        providerLock.lock()
        defer { providerLock.unlock() }
        return etfProviders.filter { $0.hasValidCredentials() }
    }
    
    // Add a new provider
    func addProvider(_ provider: APIProvider) {
        providerLock.lock()
        if provider.fetchCryptoPriceData != nil {
            if !cryptoProviders.contains(where: { $0.name == provider.name }) {
                cryptoProviders.append(provider)
            }
        }
        if provider.fetchETFPriceData != nil {
            if !etfProviders.contains(where: { $0.name == provider.name }) {
                etfProviders.append(provider)
            }
        }
        providerLock.unlock()
    }
    
    // Remove a provider
    func removeProvider(named name: String) {
        providerLock.lock()
        cryptoProviders.removeAll(where: { $0.name == name })
        etfProviders.removeAll(where: { $0.name == name })
        providerLock.unlock()
    }
    
    // MARK: - Fetch Methods
    
    // Fetch crypto price data with failover between providers
    func fetchCryptoPriceData(symbol: String) async throws -> PriceData {
        // Check cache first
        if let cachedData = APIResponseCache.shared.getCachedData(
            forKey: symbol,
            type: "crypto",
            maxAge: APIResponseCache.shared.cryptoCacheDuration
        ) {
            do {
                let priceData = try JSONDecoder().decode(PriceData.self, from: cachedData)
                return priceData
            } catch {
                print("Error decoding cached data: \(error)")
                // Continue with live data if cache decoding fails
            }
        }
        
        // Get available providers
        let providers = availableCryptoProviders
        if providers.isEmpty {
            throw NSError(domain: "APIManager", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "No valid crypto data providers available"
            ])
        }
        
        // Try each provider in order until success
        var lastError: Error?
        for provider in providers {
            do {
                let priceData = try await provider.fetchCryptoPriceData(symbol: symbol)
                
                // Cache successful response
                if let encoded = try? JSONEncoder().encode(priceData) {
                    APIResponseCache.shared.cacheData(encoded, forKey: symbol, type: "crypto")
                }
                
                return priceData
            } catch {
                print("Provider \(provider.name) failed: \(error.localizedDescription)")
                lastError = error
                continue
            }
        }
        
        // If all providers failed, throw the last error
        throw lastError ?? NSError(domain: "APIManager", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "All providers failed to fetch crypto price data"
        ])
    }
    
    // Fetch ETF price data with failover between providers
    func fetchETFPriceData(symbol: String) async throws -> PriceData {
        // Check cache first
        if let cachedData = APIResponseCache.shared.getCachedData(
            forKey: symbol,
            type: "etf",
            maxAge: APIResponseCache.shared.etfCacheDuration
        ) {
            do {
                let priceData = try JSONDecoder().decode(PriceData.self, from: cachedData)
                return priceData
            } catch {
                print("Error decoding cached data: \(error)")
                // Continue with live data if cache decoding fails
            }
        }
        
        // Get available providers
        let providers = availableETFProviders
        if providers.isEmpty {
            throw NSError(domain: "APIManager", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "No valid ETF data providers available"
            ])
        }
        
        // Try each provider in order until success
        var lastError: Error?
        for provider in providers {
            do {
                let priceData = try await provider.fetchETFPriceData(symbol: symbol)
                
                // Cache successful response
                if let encoded = try? JSONEncoder().encode(priceData) {
                    APIResponseCache.shared.cacheData(encoded, forKey: symbol, type: "etf")
                }
                
                return priceData
            } catch {
                print("Provider \(provider.name) failed: \(error.localizedDescription)")
                lastError = error
                continue
            }
        }
        
        // If all providers failed, throw the last error
        throw lastError ?? NSError(domain: "APIManager", code: 4, userInfo: [
            NSLocalizedDescriptionKey: "All providers failed to fetch ETF price data"
        ])
    }
} 