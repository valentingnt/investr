import Foundation

// MARK: - Alpha Vantage Provider
final class AlphaVantageProvider: APIProvider {
    var name: String = "Alpha Vantage"
    var baseURL: String = "https://www.alphavantage.co/query"
    var apiKeyRequired: Bool = true
    let rateLimitPerMinute = 5 // Free tier limit (5/min, 500/day)
    
    var apiKey: String {
        return APIKeyManager.shared.getAPIKey(.alphavantage) ?? ""
    }
    
    // Check if we have valid credentials
    func hasValidCredentials() -> Bool {
        return APIKeyManager.shared.hasValidAPIKey(.alphavantage)
    }
    
    // Set API key
    func setApiKey(_ key: String) {
        APIKeyManager.shared.saveAPIKey(.alphavantage, value: key)
    }
    
    // Crypto price data
    func fetchCryptoPriceData(symbol: String) async throws -> PriceData {
        // Wait for rate limit slot
        try await AdvancedAPIRateLimiter.shared.waitForSlot(endpoint: name)
        
        // Build URL for crypto endpoint
        let urlString = "\(baseURL)?function=CURRENCY_EXCHANGE_RATE&from_currency=\(symbol)&to_currency=EUR&apikey=\(apiKey)"
        
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
              let exchangeRate = json["Realtime Currency Exchange Rate"] as? [String: Any],
              let rateString = exchangeRate["5. Exchange Rate"] as? String,
              let price = Double(rateString) else {
            throw NSError(domain: name, code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Unexpected API response format"
            ])
        }
        
        // For Alpha Vantage, we need a separate call to get the daily change
        // We'll use a task group for this to simplify the code
        return try await withThrowingTaskGroup(of: PriceData.self) { group in
            // Add a task to get the daily change data
            group.addTask {
                return try await self.fetchCryptoChange(symbol: symbol, currentPrice: price)
            }
            
            // Return the result or just the price if change data fetch fails
            do {
                return try await group.next() ?? PriceData(price: price, change24h: nil)
            } catch {
                return PriceData(price: price, change24h: nil)
            }
        }
    }
    
    // Helper method to fetch crypto daily change
    private func fetchCryptoChange(symbol: String, currentPrice: Double) async throws -> PriceData {
        // Wait for rate limit slot
        try await AdvancedAPIRateLimiter.shared.waitForSlot(endpoint: name)
        
        // Build URL for daily endpoint
        let urlString = "\(baseURL)?function=DIGITAL_CURRENCY_DAILY&symbol=\(symbol)&market=EUR&apikey=\(apiKey)"
        
        guard let url = URL(string: urlString) else {
            return PriceData(price: currentPrice, change24h: nil)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        
        // Make the request
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let timeSeries = json["Time Series (Digital Currency Daily)"] as? [String: [String: String]] else {
            return PriceData(price: currentPrice, change24h: nil)
        }
        
        // Get the most recent two days of data
        let sortedDates = timeSeries.keys.sorted(by: >)
        guard sortedDates.count >= 2,
              let latestData = timeSeries[sortedDates[0]],
              let previousData = timeSeries[sortedDates[1]],
              let latestPriceStr = latestData["4a. close (EUR)"],
              let previousPriceStr = previousData["4a. close (EUR)"],
              let latestPrice = Double(latestPriceStr),
              let previousPrice = Double(previousPriceStr) else {
            return PriceData(price: currentPrice, change24h: nil)
        }
        
        // Calculate 24h change percentage
        let change24h = ((latestPrice - previousPrice) / previousPrice) * 100
        
        // Get high and low for the day
        let dayHighStr = latestData["2a. high (EUR)"]
        let dayLowStr = latestData["3a. low (EUR)"]
        
        let dayHigh = dayHighStr != nil ? Double(dayHighStr!) : nil
        let dayLow = dayLowStr != nil ? Double(dayLowStr!) : nil
        
        // Volume for the day
        let volumeStr = latestData["5. volume"]
        let volume = volumeStr != nil ? Double(volumeStr!) : nil
        
        return PriceData(
            price: currentPrice,
            change24h: change24h,
            dayHigh: dayHigh,
            dayLow: dayLow,
            previousClose: previousPrice,
            volume: volume
        )
    }
    
    // Fetch ETF/stock price data
    func fetchETFPriceData(symbol: String) async throws -> PriceData {
        // Wait for rate limit slot
        try await AdvancedAPIRateLimiter.shared.waitForSlot(endpoint: name)
        
        // Format symbol for Alpha Vantage
        var avSymbol = symbol
        if symbol.hasSuffix(".PA") {
            // Alpha Vantage uses a different format for Paris exchange: symbol.PAR
            avSymbol = symbol.replacingOccurrences(of: ".PA", with: ".PAR")
        }
        
        // Build URL for quote endpoint
        let urlString = "\(baseURL)?function=GLOBAL_QUOTE&symbol=\(avSymbol)&apikey=\(apiKey)"
        
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
              let globalQuote = json["Global Quote"] as? [String: Any],
              let priceString = globalQuote["05. price"] as? String,
              let price = Double(priceString) else {
            throw NSError(domain: name, code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Unexpected API response format"
            ])
        }
        
        // Extract additional price data
        var change24h: Double? = nil
        if let changePercentString = globalQuote["10. change percent"] as? String,
           let changePercentValue = Double(changePercentString.replacingOccurrences(of: "%", with: "")) {
            change24h = changePercentValue
        }
        
        var previousClose: Double? = nil
        if let previousCloseString = globalQuote["08. previous close"] as? String {
            previousClose = Double(previousCloseString)
        }
        
        var volume: Double? = nil
        if let volumeString = globalQuote["06. volume"] as? String {
            volume = Double(volumeString)
        }
        
        var dayHigh: Double? = nil
        var dayLow: Double? = nil
        
        // Need to get day high/low from a different endpoint
        if let highLowData = try? await fetchDayHighLow(symbol: avSymbol) {
            dayHigh = highLowData.0
            dayLow = highLowData.1
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
    
    // Helper to get day high/low from intraday data
    private func fetchDayHighLow(symbol: String) async throws -> (Double?, Double?) {
        // Wait for rate limit slot
        try await AdvancedAPIRateLimiter.shared.waitForSlot(endpoint: name)
        
        // Build URL for intraday endpoint
        let urlString = "\(baseURL)?function=TIME_SERIES_INTRADAY&symbol=\(symbol)&interval=60min&apikey=\(apiKey)"
        
        guard let url = URL(string: urlString) else {
            return (nil, nil)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        
        // Make the request
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let timeSeries = json["Time Series (60min)"] as? [String: [String: String]] else {
            return (nil, nil)
        }
        
        // Process the data to find the high and low for today
        let today = ISO8601DateFormatter().string(from: Date()).prefix(10) // Get today's date in YYYY-MM-DD format
        
        var dayHigh: Double? = nil
        var dayLow: Double? = nil
        
        // Iterate through all time points for today
        for (timeString, values) in timeSeries {
            // Check if this time point is from today
            if timeString.starts(with: today) {
                if let highString = values["2. high"], let high = Double(highString) {
                    if dayHigh == nil || high > dayHigh! {
                        dayHigh = high
                    }
                }
                
                if let lowString = values["3. low"], let low = Double(lowString) {
                    if dayLow == nil || low < dayLow! {
                        dayLow = low
                    }
                }
            }
        }
        
        return (dayHigh, dayLow)
    }
} 