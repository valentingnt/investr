import Foundation

// MARK: - CryptoCompare Provider
final class CryptoCompareProvider: APIProvider {
    let name = "cryptocompare"
    let rateLimitPerMinute = 100 // Free tier limit
    let apiKeyRequired = true
    
    // API key storage using APIKeyManager
    private var apiKey: String {
        return APIKeyManager.shared.getAPIKey(.cryptocompare)
    }
    
    // Base URL for CryptoCompare API
    private let baseURL = "https://min-api.cryptocompare.com/data"
    
    // Check if we have valid credentials
    func hasValidCredentials() -> Bool {
        return APIKeyManager.shared.hasValidAPIKey(.cryptocompare)
    }
    
    // Set API key
    func setApiKey(_ key: String) {
        APIKeyManager.shared.saveAPIKey(.cryptocompare, value: key)
    }
    
    // Fetch crypto price data for a symbol
    func fetchCryptoPriceData(symbol: String) async throws -> PriceData {
        // Wait for rate limit slot
        try await AdvancedAPIRateLimiter.shared.waitForSlot(endpoint: name)
        
        // Build URL for price endpoint
        let urlString = "\(baseURL)/price?fsym=\(symbol)&tsyms=EUR&extraParams=Investr&api_key=\(apiKey)"
        
        guard let url = URL(string: urlString) else {
            throw NSError(domain: name, code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
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
              let price = json["EUR"] as? Double else {
            throw NSError(domain: name, code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Unexpected API response format"
            ])
        }
        
        // Now get the 24h change in a separate call
        let changeUrlString = "\(baseURL)/pricemultifull?fsyms=\(symbol)&tsyms=EUR&api_key=\(apiKey)"
        
        guard let changeUrl = URL(string: changeUrlString) else {
            // Return just price if we can't get change data
            return PriceData(price: price, change24h: nil)
        }
        
        var changeRequest = URLRequest(url: changeUrl)
        changeRequest.httpMethod = "GET"
        changeRequest.timeoutInterval = 15
        
        // Wait again for rate limit to avoid hitting limits
        try await AdvancedAPIRateLimiter.shared.waitForSlot(endpoint: name)
        
        // Make the second request
        let (changeData, changeResponse) = try await URLSession.shared.data(for: changeRequest)
        
        guard let changeHttpResponse = changeResponse as? HTTPURLResponse, changeHttpResponse.statusCode == 200,
              let changeJson = try JSONSerialization.jsonObject(with: changeData) as? [String: Any],
              let raw = changeJson["RAW"] as? [String: Any],
              let symbolData = raw[symbol] as? [String: Any],
              let eurData = symbolData["EUR"] as? [String: Any] else {
            // Return just price if we can't parse change data
            return PriceData(price: price, change24h: nil)
        }
        
        // Extract additional price data
        let change24h = eurData["CHANGEPCT24HOUR"] as? Double
        let dayHigh = eurData["HIGHDAY"] as? Double
        let dayLow = eurData["LOWDAY"] as? Double
        let volume = eurData["VOLUME24HOUR"] as? Double
        
        return PriceData(
            price: price,
            change24h: change24h,
            dayHigh: dayHigh,
            dayLow: dayLow,
            previousClose: nil,
            volume: volume
        )
    }
    
    // ETF price data - not available from CryptoCompare
    func fetchETFPriceData(symbol: String) async throws -> PriceData {
        throw NSError(domain: name, code: 5, userInfo: [
            NSLocalizedDescriptionKey: "ETF data not available from CryptoCompare"
        ])
    }
} 