import Foundation

// MARK: - CoinAPI Provider
final class CoinAPIProvider: APIProvider {
    var name: String = "CoinAPI"
    var baseURL: String = "https://rest.coinapi.io/v1"
    var apiKeyRequired: Bool = true
    let rateLimitPerMinute = 100 // Free tier daily limit distributed
    
    var apiKey: String {
        return APIKeyManager.shared.getAPIKey(.coinapi) ?? ""
    }
    
    func hasValidCredentials() -> Bool {
        return APIKeyManager.shared.hasValidAPIKey(.coinapi)
    }
    
    func setApiKey(_ key: String) {
        APIKeyManager.shared.saveAPIKey(.coinapi, value: key)
    }
    
    // Fetch crypto price data
    func fetchCryptoPriceData(symbol: String) async throws -> PriceData {
        // Wait for rate limit slot
        try await AdvancedAPIRateLimiter.shared.waitForSlot(endpoint: name)
        
        // Format symbol for CoinAPI
        let formattedSymbol = "\(symbol)/EUR"
        
        // Build URL for exchange rate endpoint
        let urlString = "\(baseURL)/exchangerate/\(symbol)/EUR"
        
        guard let url = URL(string: urlString) else {
            throw NSError(domain: name, code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "X-CoinAPI-Key")
        request.timeoutInterval = 15
        
        // Make the request
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: name, code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response"])
        }
        
        // Check for errors
        if httpResponse.statusCode != 200 {
            throw NSError(domain: name, code: httpResponse.statusCode, userInfo: [
                NSLocalizedDescriptionKey: "HTTP Error: \(httpResponse.statusCode)"
            ])
        }
        
        // Parse the response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rate = json["rate"] as? Double else {
            throw NSError(domain: name, code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Unexpected API response format"
            ])
        }
        
        // Get additional data like 24h change from a separate endpoint
        let priceData = try await fetchAdditionalCryptoData(symbol: symbol, currentPrice: rate)
        
        return priceData
    }
    
    // Helper to fetch additional crypto data
    private func fetchAdditionalCryptoData(symbol: String, currentPrice: Double) async throws -> PriceData {
        // Wait for rate limit slot
        try await AdvancedAPIRateLimiter.shared.waitForSlot(endpoint: name)
        
        // Get current date and date 24h ago
        let now = Date()
        let yesterday = now.addingTimeInterval(-24 * 60 * 60)
        
        // Format dates
        let dateFormatter = ISO8601DateFormatter()
        let endTime = dateFormatter.string(from: now)
        let startTime = dateFormatter.string(from: yesterday)
        
        // Build URL for OHLCV data
        let urlString = "\(baseURL)/ohlcv/\(symbol)/EUR/latest?period_id=1DAY&time_start=\(startTime)&time_end=\(endTime)"
        
        guard let url = URL(string: urlString) else {
            // Return just the price if we can't get additional data
            return PriceData(price: currentPrice, change24h: nil)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "X-CoinAPI-Key")
        request.timeoutInterval = 15
        
        do {
            // Make the request
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
                  let ohlcvData = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let latestData = ohlcvData.first else {
                // Return just the price if we can't parse the response
                return PriceData(price: currentPrice, change24h: nil)
            }
            
            // Extract data from OHLCV response
            let openPrice = latestData["price_open"] as? Double ?? currentPrice
            let highPrice = latestData["price_high"] as? Double
            let lowPrice = latestData["price_low"] as? Double
            let volume = latestData["volume_traded"] as? Double
            
            // Calculate 24h change
            let change24h = ((currentPrice - openPrice) / openPrice) * 100
            
            return PriceData(
                price: currentPrice,
                change24h: change24h,
                dayHigh: highPrice,
                dayLow: lowPrice,
                previousClose: openPrice,
                volume: volume
            )
        } catch {
            // Return just the price if there's an error
            return PriceData(price: currentPrice, change24h: nil)
        }
    }
    
    // ETF price data - not available from CoinAPI
    func fetchETFPriceData(symbol: String) async throws -> PriceData {
        throw NSError(domain: name, code: 5, userInfo: [
            NSLocalizedDescriptionKey: "ETF data not available from CoinAPI"
        ])
    }
} 