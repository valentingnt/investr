import Foundation

// MARK: - ETF Service
final class ETFService: BaseAssetService, AssetServiceProtocol {
    // Emergency fallback data for common ETFs and stocks
    private let emergencyPriceData: [String: PriceData] = [
        "AAPL": PriceData(price: 180.75, change24h: 0.5),
        "MSFT": PriceData(price: 410.34, change24h: 0.3),
        "GOOGL": PriceData(price: 175.50, change24h: -0.2),
        "AMZN": PriceData(price: 185.25, change24h: 0.8),
        "VOO": PriceData(price: 470.80, change24h: 0.1),
        "SPY": PriceData(price: 510.40, change24h: 0.2),
        "WPEA.PA": PriceData(price: 21.15, change24h: 0.3),
        "ESE.PA": PriceData(price: 63.78, change24h: 0.2)
    ]
    
    // Cache for API responses to reduce redundant API calls
    private var priceCache: [String: (price: PriceData, timestamp: Date)] = [:]
    private let priceCacheLock = NSLock()
    private let priceCacheDuration: TimeInterval = 15 * 60 // 15 minutes
    
    func enrichAssetWithPriceAndTransactions(
        asset: Asset,
        transactions: [Transaction]
    ) async -> AssetViewModel? {
        do {
            print("ETFService: Getting price for \(asset.symbol)")
            let priceData = try await fetchPrice(symbol: asset.symbol)
            return createBaseViewModel(asset: asset, priceData: priceData, transactions: transactions)
        } catch {
            print("⚠️ ETFService error for \(asset.symbol): \(error.localizedDescription)")
            
            // Try fallback data if available
            if let fallback = emergencyPriceData[asset.symbol] {
                print("Using fallback data for \(asset.symbol)")
                return createBaseViewModel(asset: asset, priceData: fallback, transactions: transactions)
            }
            
            // Return a basic model with no price data
            return createBaseViewModel(asset: asset, priceData: nil, transactions: transactions)
        }
    }
    
    private func fetchPrice(symbol: String) async throws -> PriceData {
        // Check in-memory cache first
        let now = Date()
        priceCacheLock.lock()
        if let cached = priceCache[symbol], 
           now.timeIntervalSince(cached.timestamp) < priceCacheDuration {
            // Use cached data if recent
            priceCacheLock.unlock()
            return cached.price
        }
        priceCacheLock.unlock()
        
        // Wait for an available slot in the rate limiter
        try await APIRateLimiter.shared.waitForSlot(endpoint: "yahoo-finance")
        
        // Handle different stock exchange suffixes
        let yahooSymbol = symbol.contains(".") ? symbol : "\(symbol).PA"
        let encodedSymbol = yahooSymbol.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? yahooSymbol
        let urlString = "https://apidojo-yahoo-finance-v1.p.rapidapi.com/market/v2/get-quotes?region=FR&symbols=\(encodedSymbol)"
        
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "ETFService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("apidojo-yahoo-finance-v1.p.rapidapi.com", forHTTPHeaderField: "X-RapidAPI-Host")
        request.timeoutInterval = 15 // Increased timeout for reliability
        
        guard let rapidApiKey = ProcessInfo.processInfo.environment["RAPIDAPI_KEY"],
              !rapidApiKey.isEmpty else {
            throw NSError(domain: "ETFService", code: 1, userInfo: [NSLocalizedDescriptionKey: "RAPIDAPI_KEY environment variable is not set"])
        }
        
        request.setValue(rapidApiKey, forHTTPHeaderField: "X-RapidAPI-Key")
        
        do {
            // Use a task group for timeout handling
            return try await withThrowingTaskGroup(of: PriceData.self) { group in
                // Add the actual API call task
                group.addTask {
                    let (data, response) = try await URLSession.shared.data(for: request)
                    
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw NSError(domain: "ETFService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response"])
                    }
                    
                    if httpResponse.statusCode != 200 {
                        throw NSError(domain: "ETFService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP Error: \(httpResponse.statusCode)"])
                    }
                    
                    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                    guard let quoteResponse = json?["quoteResponse"] as? [String: Any],
                          let results = quoteResponse["result"] as? [[String: Any]],
                          let result = results.first,
                          let price = result["regularMarketPrice"] as? Double else {
                        throw NSError(domain: "ETFService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unexpected API response format"])
                    }
                    
                    let priceData = PriceData(
                        price: price,
                        change24h: result["regularMarketChangePercent"] as? Double,
                        dayHigh: result["regularMarketDayHigh"] as? Double,
                        dayLow: result["regularMarketDayLow"] as? Double,
                        previousClose: result["regularMarketPreviousClose"] as? Double,
                        volume: result["regularMarketVolume"] as? Double
                    )
                    
                    // Cache the successful result
                    self.priceCacheLock.lock()
                    self.priceCache[symbol] = (priceData, Date())
                    self.priceCacheLock.unlock()
                    
                    return priceData
                }
                
                // Return the first result or throw an error
                return try await group.next() ?? PriceData.empty()
            }
        } catch {
            // For severe errors, try to provide fallback data
            if let fallback = emergencyPriceData[symbol] {
                return fallback
            }
            throw error
        }
    }
} 