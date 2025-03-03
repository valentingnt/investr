import Foundation

// MARK: - Financial Modeling Prep Provider
final class FinancialModelingPrepProvider: APIProvider {
    var name: String = "Financial Modeling Prep"
    var baseURL: String = "https://financialmodelingprep.com/api/v3"
    var apiKeyRequired: Bool = true
    let rateLimitPerMinute = 300 // Free tier limit (300/day, but we'll distribute)
    
    var apiKey: String {
        return APIKeyManager.shared.getAPIKey(.financialModelingPrep) ?? ""
    }
    
    func hasValidCredentials() -> Bool {
        return APIKeyManager.shared.hasValidAPIKey(.financialModelingPrep)
    }
    
    func setApiKey(_ key: String) {
        APIKeyManager.shared.saveAPIKey(.financialModelingPrep, value: key)
    }
    
    // Crypto price data - limited on FMP, use as fallback only
    func fetchCryptoPriceData(symbol: String) async throws -> PriceData {
        // Wait for rate limit slot
        try await AdvancedAPIRateLimiter.shared.waitForSlot(endpoint: name)
        
        // Adjust symbol for FMP format
        let cryptoSymbol = symbol.uppercased() + "USD"
        
        // Build URL for quote endpoint
        let urlString = "\(baseURL)/quote/\(cryptoSymbol)?apikey=\(apiKey)"
        
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
        guard let quotes = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let quote = quotes.first,
              let price = quote["price"] as? Double else {
            throw NSError(domain: name, code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Unexpected API response format"
            ])
        }
        
        // Extract additional price data
        let change24h = quote["changesPercentage"] as? Double
        let dayHigh = quote["dayHigh"] as? Double
        let dayLow = quote["dayLow"] as? Double
        let previousClose = quote["previousClose"] as? Double
        let volume = quote["volume"] as? Double
        
        // Convert USD to EUR (simplistic conversion for now)
        let estimatedEurPrice = price * 0.92 // Approximate USD to EUR conversion
        
        return PriceData(
            price: estimatedEurPrice,
            change24h: change24h,
            dayHigh: dayHigh != nil ? dayHigh! * 0.92 : nil,
            dayLow: dayLow != nil ? dayLow! * 0.92 : nil,
            previousClose: previousClose != nil ? previousClose! * 0.92 : nil,
            volume: volume
        )
    }
    
    // Fetch ETF/stock price data
    func fetchETFPriceData(symbol: String) async throws -> PriceData {
        // Wait for rate limit slot
        try await AdvancedAPIRateLimiter.shared.waitForSlot(endpoint: name)
        
        // Adjust symbol if needed
        var fmpSymbol = symbol
        if symbol.contains(".PA") {
            // Remove .PA suffix and add Paris exchange identifier
            fmpSymbol = symbol.replacingOccurrences(of: ".PA", with: "")
        }
        
        // Build URL for quote endpoint
        let urlString = "\(baseURL)/quote/\(fmpSymbol)?apikey=\(apiKey)"
        
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
        guard let quotes = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let quote = quotes.first,
              let price = quote["price"] as? Double else {
            throw NSError(domain: name, code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Unexpected API response format"
            ])
        }
        
        // Extract additional price data
        let change24h = quote["changesPercentage"] as? Double
        let dayHigh = quote["dayHigh"] as? Double
        let dayLow = quote["dayLow"] as? Double
        let previousClose = quote["previousClose"] as? Double
        let volume = quote["volume"] as? Double
        
        return PriceData(
            price: price,
            change24h: change24h,
            dayHigh: dayHigh,
            dayLow: dayLow,
            previousClose: previousClose,
            volume: volume
        )
    }
} 