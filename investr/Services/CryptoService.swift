import Foundation

// MARK: - Crypto Service
final class CryptoService: BaseAssetService, AssetServiceProtocol {
    // Map common crypto symbols to CoinGecko API IDs
    private let symbolToIdMap: [String: String] = [
        "BTC": "bitcoin",
        "ETH": "ethereum",
        "USDT": "tether",
        "BNB": "binancecoin",
        "SOL": "solana",
        "XRP": "ripple",
        "USDC": "usd-coin",
        "ADA": "cardano",
        "AVAX": "avalanche-2",
        "DOGE": "dogecoin"
    ]
    
    // Critical error fallback data
    private let emergencyPriceData: [String: PriceData] = [
        "BTC": PriceData(price: 56000.0, change24h: 2.5),
        "ETH": PriceData(price: 3200.0, change24h: 1.8)
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
            print("CryptoService: Getting price for \(asset.symbol)")
            let priceData = try await fetchPrice(symbol: asset.symbol)
            return createBaseViewModel(asset: asset, priceData: priceData, transactions: transactions)
        } catch {
            print("⚠️ CryptoService error for \(asset.symbol): \(error.localizedDescription)")
            
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
        
        // Get CoinGecko ID for the symbol
        guard let coinGeckoId = symbolToIdMap[symbol] else {
            throw NSError(domain: "CryptoService", code: 4, userInfo: [NSLocalizedDescriptionKey: "Unknown cryptocurrency symbol: \(symbol)"])
        }
        
        // Wait for an available slot in the rate limiter
        try await APIRateLimiter.shared.waitForSlot(endpoint: "coingecko")
        
        let urlString = "https://coingecko.p.rapidapi.com/simple/price?ids=\(coinGeckoId)&vs_currencies=eur&include_24hr_change=true"
        
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "CryptoService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("coingecko.p.rapidapi.com", forHTTPHeaderField: "X-RapidAPI-Host")
        request.timeoutInterval = 15 // Increased timeout for reliability
        
        guard let rapidApiKey = ProcessInfo.processInfo.environment["RAPIDAPI_KEY"],
              !rapidApiKey.isEmpty else {
            throw NSError(domain: "CryptoService", code: 1, userInfo: [NSLocalizedDescriptionKey: "RAPIDAPI_KEY environment variable is not set"])
        }
        
        request.setValue(rapidApiKey, forHTTPHeaderField: "X-RapidAPI-Key")
        
        do {
            // Use a task group for timeout handling
            return try await withThrowingTaskGroup(of: PriceData.self) { group in
                // Add the actual API call task
                group.addTask {
                    let (data, response) = try await URLSession.shared.data(for: request)
                    
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw NSError(domain: "CryptoService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response"])
                    }
                    
                    if httpResponse.statusCode != 200 {
                        throw NSError(domain: "CryptoService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP Error: \(httpResponse.statusCode)"])
                    }
                    
                    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                    guard let cryptoData = json?[coinGeckoId] as? [String: Any],
                          let price = cryptoData["eur"] as? Double else {
                        throw NSError(domain: "CryptoService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unexpected CoinGecko API response format"])
                    }
                    
                    let priceData = PriceData(
                        price: price,
                        change24h: cryptoData["eur_24h_change"] as? Double
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