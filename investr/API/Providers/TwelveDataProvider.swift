import Foundation

// MARK: - TwelveData Provider
final class TwelveDataProvider: APIProvider {
    var name: String = "TwelveData"
    var baseURL: String = "https://api.twelvedata.com"
    var apiKeyRequired: Bool = true
    let rateLimitPerMinute = 8 // Free tier limit (8/min, 800/day)
    
    var apiKey: String {
        return APIKeyManager.shared.getAPIKey(.twelvedata) ?? ""
    }
    
    // Check if we have valid credentials
    func hasValidCredentials() -> Bool {
        return APIKeyManager.shared.hasValidAPIKey(.twelvedata)
    }
    
    // Set API key
    func setApiKey(_ key: String) {
        APIKeyManager.shared.saveAPIKey(.twelvedata, value: key)
    }
    
    // Fetch ETF/stock price data
    func fetchETFPriceData(symbol: String) async throws -> PriceData {
        // Wait for rate limit slot
        try await AdvancedAPIRateLimiter.shared.waitForSlot(endpoint: name)
        
        // Format symbol for TwelveData (handle Paris exchange)
        var tdSymbol = symbol
        if symbol.hasSuffix(".PA") {
            // TwelveData uses a different format for Paris exchange
            tdSymbol = symbol.replacingOccurrences(of: ".PA", with: ".PARIS")
        }
        
        // Build URL for quote endpoint
        let urlString = "\(baseURL)/quote?symbol=\(tdSymbol)&apikey=\(apiKey)"
        
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
              let priceString = json["close"] as? String,
              let price = Double(priceString) else {
            throw NSError(domain: name, code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Unexpected API response format"
            ])
        }
        
        // Extract additional price data
        var change24h: Double? = nil
        if let percentChangeString = json["percent_change"] as? String,
           let percentChange = Double(percentChangeString) {
            change24h = percentChange
        }
        
        var previousClose: Double? = nil
        if let previousCloseString = json["previous_close"] as? String {
            previousClose = Double(previousCloseString)
        }
        
        var dayHigh: Double? = nil
        if let dayHighString = json["high"] as? String {
            dayHigh = Double(dayHighString)
        }
        
        var dayLow: Double? = nil
        if let dayLowString = json["low"] as? String {
            dayLow = Double(dayLowString)
        }
        
        var volume: Double? = nil
        if let volumeString = json["volume"] as? String {
            volume = Double(volumeString)
        }
        
        return PriceData(
            price: price,
            change24h: change24h,
            dayHigh: dayHigh,
            dayLow: dayLow,
            previousClose: previousClose,
            volume: volume
        )
    }
    
    // Crypto price data - limited coverage on TwelveData
    func fetchCryptoPriceData(symbol: String) async throws -> PriceData {
        // Wait for rate limit slot
        try await AdvancedAPIRateLimiter.shared.waitForSlot(endpoint: name)
        
        // Format symbol for TwelveData crypto format
        let cryptoSymbol = "\(symbol)/EUR"
        
        // Build URL for price endpoint
        let urlString = "\(baseURL)/quote?symbol=\(cryptoSymbol)&apikey=\(apiKey)"
        
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
        
        // Check if we received an error response from the API
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let _ = json["code"] as? String,
           let status = json["status"] as? String, status == "error" {
            throw NSError(domain: name, code: 4, userInfo: [
                NSLocalizedDescriptionKey: "TwelveData does not support this cryptocurrency"
            ])
        }
        
        // Parse the response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let priceString = json["close"] as? String,
              let price = Double(priceString) else {
            throw NSError(domain: name, code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Unexpected API response format"
            ])
        }
        
        // Extract additional price data
        var change24h: Double? = nil
        if let percentChangeString = json["percent_change"] as? String,
           let percentChange = Double(percentChangeString) {
            change24h = percentChange
        }
        
        var dayHigh: Double? = nil
        if let dayHighString = json["high"] as? String {
            dayHigh = Double(dayHighString)
        }
        
        var dayLow: Double? = nil
        if let dayLowString = json["low"] as? String {
            dayLow = Double(dayLowString)
        }
        
        var previousClose: Double? = nil
        if let previousCloseString = json["previous_close"] as? String {
            previousClose = Double(previousCloseString)
        }
        
        var volume: Double? = nil
        if let volumeString = json["volume"] as? String {
            volume = Double(volumeString)
        }
        
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