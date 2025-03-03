import Foundation

// MARK: - CoinGecko Provider
final class CoinGeckoProvider: APIProvider {
    let name = "coingecko"
    let rateLimitPerMinute = 10 // Free tier limit (10-50/min depending on endpoint)
    let apiKeyRequired = false // Can work without a key, but better with one
    
    // API keys storage using APIKeyManager
    private var apiKey: String {
        return APIKeyManager.shared.getAPIKey(.coingecko)
    }
    
    private var rapidApiKey: String {
        return APIKeyManager.shared.getAPIKey(.rapidapi)
    }
    
    // Direct API or RapidAPI gateway mode
    private var useDirectApi: Bool {
        return !apiKey.isEmpty
    }
    
    // Base URLs
    private let directBaseURL = "https://api.coingecko.com/api/v3"
    private let rapidBaseURL = "https://coingecko.p.rapidapi.com"
    
    // Symbol to ID mapping
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
        "DOGE": "dogecoin",
        "DOT": "polkadot",
        "MATIC": "polygon",
        "LTC": "litecoin",
        "UNI": "uniswap",
        "LINK": "chainlink",
        "SHIB": "shiba-inu",
        "XLM": "stellar",
        "ATOM": "cosmos",
        "TRX": "tron",
        "XMR": "monero"
    ]
    
    // Check if we have valid credentials
    func hasValidCredentials() -> Bool {
        // We can use direct API with free tier or with API key
        // Or we can use RapidAPI if we have a key
        return useDirectApi || APIKeyManager.shared.hasValidAPIKey(.rapidapi)
    }
    
    // Set CoinGecko API key
    func setApiKey(_ key: String) {
        APIKeyManager.shared.saveAPIKey(.coingecko, value: key)
    }
    
    // Set RapidAPI key
    func setRapidApiKey(_ key: String) {
        APIKeyManager.shared.saveAPIKey(.rapidapi, value: key)
    }
    
    // Fetch crypto price data
    func fetchCryptoPriceData(symbol: String) async throws -> PriceData {
        // Get CoinGecko ID for the symbol
        guard let coinGeckoId = symbolToIdMap[symbol] else {
            throw NSError(domain: name, code: 4, userInfo: [
                NSLocalizedDescriptionKey: "Unknown cryptocurrency symbol: \(symbol)"
            ])
        }
        
        // Wait for rate limit slot
        try await AdvancedAPIRateLimiter.shared.waitForSlot(endpoint: name)
        
        // Use direct API or RapidAPI based on available keys
        if useDirectApi {
            return try await fetchDirectCoinGeckoData(id: coinGeckoId)
        } else {
            return try await fetchRapidApiCoinGeckoData(id: coinGeckoId)
        }
    }
    
    // Fetch data directly from CoinGecko API
    private func fetchDirectCoinGeckoData(id: String) async throws -> PriceData {
        // Build URL for price endpoint
        let urlString = "\(directBaseURL)/simple/price?ids=\(id)&vs_currencies=eur&include_24hr_change=true&include_24hr_vol=true&include_last_updated_at=true"
        var urlComponents = URLComponents(string: urlString)
        
        // Add API key if available
        if !apiKey.isEmpty {
            let queryItems = [URLQueryItem(name: "x_cg_pro_api_key", value: apiKey)]
            urlComponents?.queryItems = queryItems
        }
        
        guard let url = urlComponents?.url else {
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
              let cryptoData = json[id] as? [String: Any],
              let price = cryptoData["eur"] as? Double else {
            throw NSError(domain: name, code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Unexpected CoinGecko API response format"
            ])
        }
        
        // Extract additional data
        let change24h = cryptoData["eur_24h_change"] as? Double
        let volume = cryptoData["eur_24h_vol"] as? Double
        
        // Get more detailed data if needed
        var dayHigh: Double? = nil
        var dayLow: Double? = nil
        var previousClose: Double? = nil
        
        // For free tier, we only get the basic data
        // With a paid API key, we could fetch more detailed data
        
        return PriceData(
            price: price,
            change24h: change24h,
            dayHigh: dayHigh,
            dayLow: dayLow,
            previousClose: previousClose,
            volume: volume
        )
    }
    
    // Fetch using RapidAPI gateway
    private func fetchRapidApiCoinGeckoData(id: String) async throws -> PriceData {
        // Build URL for price endpoint
        let urlString = "\(rapidBaseURL)/simple/price?ids=\(id)&vs_currencies=eur&include_24hr_change=true"
        
        guard let url = URL(string: urlString) else {
            throw NSError(domain: name, code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("coingecko.p.rapidapi.com", forHTTPHeaderField: "X-RapidAPI-Host")
        request.setValue(rapidApiKey, forHTTPHeaderField: "X-RapidAPI-Key")
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
              let cryptoData = json[id] as? [String: Any],
              let price = cryptoData["eur"] as? Double else {
            throw NSError(domain: name, code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Unexpected CoinGecko API response format"
            ])
        }
        
        // Extract 24h change
        let change24h = cryptoData["eur_24h_change"] as? Double
        
        return PriceData(
            price: price,
            change24h: change24h,
            dayHigh: nil,
            dayLow: nil,
            previousClose: nil,
            volume: nil
        )
    }
    
    // ETF price data - not available from CoinGecko
    func fetchETFPriceData(symbol: String) async throws -> PriceData {
        throw NSError(domain: name, code: 5, userInfo: [
            NSLocalizedDescriptionKey: "ETF data not available from CoinGecko"
        ])
    }
} 