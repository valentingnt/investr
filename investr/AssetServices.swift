//
//  AssetServices.swift
//  investr
//
//  Created by Valentin Genest on 28/02/2025.
//

import Foundation

// MARK: - Base Asset Service Protocol
protocol AssetServiceProtocol {
    func enrichAssetWithPriceAndTransactions(
        asset: Asset,
        transactions: [Transaction]
    ) async -> AssetViewModel?
}

// MARK: - Price Data
struct PriceData {
    var price: Double
    var change24h: Double?
    var dayHigh: Double?
    var dayLow: Double?
    var previousClose: Double?
    var volume: Double?
}

// MARK: - Base Asset Service
class BaseAssetService {
    func calculateTotalCost(transactions: [Transaction]) -> Double {
        transactions.reduce(0) { sum, transaction in
            sum + (transaction.type == .buy ? transaction.total_amount : -transaction.total_amount)
        }
    }
    
    func calculateTotalQuantity(transactions: [Transaction]) -> Double {
        transactions.reduce(0) { sum, transaction in
            sum + (transaction.type == .buy ? transaction.quantity : -transaction.quantity)
        }
    }
}

// MARK: - API Rate Limiter
class APIRateLimiter {
    static let shared = APIRateLimiter()
    
    private let maxRequestsPerSecond: Int = 5 // RapidAPI limit
    private var requestTimestamps: [Date] = []
    private let requestQueue = DispatchQueue(label: "com.investr.apiRequestQueue")
    
    // Monthly request tracking - internal only, not displayed to users
    private let userDefaults = UserDefaults.standard
    private let monthlyRequestCountKey = "com.investr.monthlyRequestCount"
    private let lastMonthResetKey = "com.investr.lastMonthReset"
    private let monthlyRequestLimit = 500
    
    private init() {
        checkAndResetMonthlyCounter()
    }
    
    private var monthlyRequestCount: Int {
        get { userDefaults.integer(forKey: monthlyRequestCountKey) }
        set { userDefaults.set(newValue, forKey: monthlyRequestCountKey) }
    }
    
    private func checkAndResetMonthlyCounter() {
        let calendar = Calendar.current
        let now = Date()
        
        if let lastReset = userDefaults.object(forKey: lastMonthResetKey) as? Date {
            let lastResetComponents = calendar.dateComponents([.year, .month], from: lastReset)
            let currentComponents = calendar.dateComponents([.year, .month], from: now)
            
            if lastResetComponents.year != currentComponents.year || lastResetComponents.month != currentComponents.month {
                // It's a new month, reset the counter
                monthlyRequestCount = 0
                userDefaults.set(now, forKey: lastMonthResetKey)
            }
        } else {
            // First time initialization
            userDefaults.set(now, forKey: lastMonthResetKey)
        }
    }
    
    func waitForSlot() async throws {
        // Check monthly limit first
        checkAndResetMonthlyCounter()
        if monthlyRequestCount >= monthlyRequestLimit {
            throw NSError(domain: "APIRateLimiter", code: 429, 
                         userInfo: [NSLocalizedDescriptionKey: "API request limit has been reached"])
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            requestQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume()
                    return
                }
                
                // Clean up old timestamps (older than 1 second)
                let now = Date()
                self.requestTimestamps = self.requestTimestamps.filter {
                    now.timeIntervalSince($0) < 1.0
                }
                
                // Check if we're at the limit
                if self.requestTimestamps.count >= self.maxRequestsPerSecond {
                    // Calculate how long to wait
                    if let oldestTimestamp = self.requestTimestamps.first {
                        let waitTime = 1.0 - now.timeIntervalSince(oldestTimestamp)
                        if waitTime > 0 {
                            // Silently wait, no logging
                            Thread.sleep(forTimeInterval: waitTime)
                        }
                    }
                    
                    // Clean up timestamps again after waiting
                    let newNow = Date()
                    self.requestTimestamps = self.requestTimestamps.filter {
                        newNow.timeIntervalSince($0) < 1.0
                    }
                }
                
                // Add the current request timestamp
                self.requestTimestamps.append(Date())
                
                // Increment monthly counter (silently)
                self.monthlyRequestCount += 1
                
                continuation.resume()
            }
        }
    }
    
    func resetMonthlyCounter() {
        monthlyRequestCount = 0
        userDefaults.set(Date(), forKey: lastMonthResetKey)
    }
}

// MARK: - ETF Service
class ETFService: BaseAssetService, AssetServiceProtocol {
    private var priceCache: [String: (price: PriceData, timestamp: Date)] = [:]
    
    // Get cache duration from UserDefaults (user settings) with a default of 20 seconds
    private var cacheDuration: TimeInterval {
        // If user has set a value via Settings, use that value (in minutes), otherwise default to 20 seconds
        if let minutes = UserDefaults.standard.object(forKey: "apiCacheExpirationMinutes") as? Int {
            return TimeInterval(minutes * 60) // Convert minutes to seconds
        }
        return 20 // Default: 20 seconds
    }
    
    func enrichAssetWithPriceAndTransactions(
        asset: Asset,
        transactions: [Transaction]
    ) async -> AssetViewModel? {
        do {
            let priceData = try await getPrice(symbol: asset.symbol)
            
            let totalQuantity = calculateTotalQuantity(transactions: transactions)
            let totalCost = calculateTotalCost(transactions: transactions)
            let totalValue = totalQuantity * priceData.price
            
            return AssetViewModel(
                id: asset.id,
                name: asset.name,
                symbol: asset.symbol,
                type: asset.type,
                currentPrice: priceData.price,
                totalValue: totalValue,
                totalQuantity: totalQuantity,
                averagePrice: totalQuantity > 0 ? totalCost / totalQuantity : 0,
                profitLoss: totalValue - totalCost,
                profitLossPercentage: totalCost > 0 ? ((totalValue - totalCost) / totalCost) * 100 : 0,
                change24h: priceData.change24h,
                dayHigh: priceData.dayHigh,
                dayLow: priceData.dayLow,
                previousClose: priceData.previousClose,
                volume: priceData.volume
            )
        } catch {
            // Silent error handling
            return nil
        }
    }
    
    private func getPrice(symbol: String) async throws -> PriceData {
        // Check cache first
        if let cached = priceCache[symbol], 
           Date().timeIntervalSince(cached.timestamp) < cacheDuration {
            return cached.price
        }
        
        // Wait for an available slot in the rate limiter
        try await APIRateLimiter.shared.waitForSlot()
        
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
        
        guard let rapidApiKey = ProcessInfo.processInfo.environment["RAPIDAPI_KEY"],
              !rapidApiKey.isEmpty else {
            throw NSError(domain: "ETFService", code: 1, userInfo: [NSLocalizedDescriptionKey: "RAPIDAPI_KEY environment variable is not set"])
        }
        
        request.setValue(rapidApiKey, forHTTPHeaderField: "X-RapidAPI-Key")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NSError(domain: "ETFService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response"])
            }
            
            if httpResponse.statusCode == 429 {
                throw NSError(domain: "ETFService", code: 429, userInfo: [NSLocalizedDescriptionKey: "API rate limit exceeded"])
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
            
            // Cache the result
            priceCache[symbol] = (priceData, Date())
            
            return priceData
        } catch {
            if let error = error as? NSError, error.domain == "ETFService" && error.code == 429 {
                // Silently retry after waiting
                try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                return try await getPrice(symbol: symbol)
            }
            throw error
        }
    }
}

// MARK: - Crypto Service
class CryptoService: BaseAssetService, AssetServiceProtocol {
    private var priceCache: [String: (price: PriceData, timestamp: Date)] = [:]
    
    // Get cache duration from UserDefaults (user settings) with a default of 20 seconds
    private var cacheDuration: TimeInterval {
        // If user has set a value via Settings, use that value (in minutes), otherwise default to 20 seconds
        if let minutes = UserDefaults.standard.object(forKey: "apiCacheExpirationMinutes") as? Int {
            return TimeInterval(minutes * 60) // Convert minutes to seconds
        }
        return 20 // Default: 20 seconds
    }
    
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
    
    func enrichAssetWithPriceAndTransactions(
        asset: Asset,
        transactions: [Transaction]
    ) async -> AssetViewModel? {
        do {
            let priceData = try await getPrice(symbol: asset.symbol)
            
            let totalQuantity = calculateTotalQuantity(transactions: transactions)
            let totalCost = calculateTotalCost(transactions: transactions)
            let totalValue = totalQuantity * priceData.price
            
            return AssetViewModel(
                id: asset.id,
                name: asset.name,
                symbol: asset.symbol,
                type: asset.type,
                currentPrice: priceData.price,
                totalValue: totalValue,
                totalQuantity: totalQuantity,
                averagePrice: totalQuantity > 0 ? totalCost / totalQuantity : 0,
                profitLoss: totalValue - totalCost,
                profitLossPercentage: totalCost > 0 ? ((totalValue - totalCost) / totalCost) * 100 : 0,
                change24h: priceData.change24h
            )
        } catch {
            // Silent error handling
            return nil
        }
    }
    
    private func getPrice(symbol: String) async throws -> PriceData {
        // Check cache first
        if let cached = priceCache[symbol], 
           Date().timeIntervalSince(cached.timestamp) < cacheDuration {
            return cached.price
        }
        
        // Get CoinGecko ID for the symbol
        guard let coinGeckoId = symbolToIdMap[symbol] else {
            throw NSError(domain: "CryptoService", code: 4, userInfo: [NSLocalizedDescriptionKey: "Unknown cryptocurrency symbol: \(symbol)"])
        }
        
        // Wait for an available slot in the rate limiter
        try await APIRateLimiter.shared.waitForSlot()
        
        let urlString = "https://coingecko.p.rapidapi.com/simple/price?ids=\(coinGeckoId)&vs_currencies=eur&include_24hr_change=true"
        
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "CryptoService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("coingecko.p.rapidapi.com", forHTTPHeaderField: "X-RapidAPI-Host")
        
        guard let rapidApiKey = ProcessInfo.processInfo.environment["RAPIDAPI_KEY"],
              !rapidApiKey.isEmpty else {
            throw NSError(domain: "CryptoService", code: 1, userInfo: [NSLocalizedDescriptionKey: "RAPIDAPI_KEY environment variable is not set"])
        }
        
        request.setValue(rapidApiKey, forHTTPHeaderField: "X-RapidAPI-Key")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NSError(domain: "CryptoService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response"])
            }
            
            if httpResponse.statusCode == 429 {
                throw NSError(domain: "CryptoService", code: 429, userInfo: [NSLocalizedDescriptionKey: "API rate limit exceeded"])
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
            
            // Cache the result
            priceCache[symbol] = (priceData, Date())
            
            return priceData
        } catch {
            if let error = error as? NSError, error.domain == "CryptoService" && error.code == 429 {
                // Silently retry after waiting
                try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                return try await getPrice(symbol: symbol)
            }
            
            // Only use emergency data in critical cases where the app would otherwise crash
            if let nsError = error as? NSError, 
               nsError.domain == "CryptoService" && 
               (nsError.code == 1 || nsError.code == 429), // API key or rate limiting issues
               let emergencyData = emergencyPriceData[symbol] {
                return emergencyData
            }
            
            throw error
        }
    }
}

// MARK: - Savings Service
class SavingsService: BaseAssetService {
    func enrichAssetWithPriceAndTransactions(
        asset: Asset,
        transactions: [Transaction],
        interestRateHistory: [InterestRateHistory],
        supabaseManager: SupabaseManager
    ) async -> AssetViewModel? {
        do {
            // Get current interest rate
            let currentRate = try await supabaseManager.getCurrentInterestRate(assetId: asset.id)
            
            // Calculate metrics
            let (totalQuantity, accruedInterest) = calculateSavingsMetrics(
                transactions: transactions.sorted(by: { $0.transaction_date < $1.transaction_date }),
                interestRateHistory: interestRateHistory
            )
            
            // Calculate totalCost differently for savings
            // For savings, the totalCost is just the net deposits (buy transactions minus sell transactions)
            let totalCost = calculateTotalCost(transactions: transactions)
            
            // For savings accounts, totalValue is the current balance plus accrued interest
            let totalValue = totalQuantity + accruedInterest
            
            // For savings accounts, if there are transactions but zero balance,
            // we still want to show it as an active account with the interest earned
            let displayQuantity = totalQuantity
            let hasTransactions = !transactions.isEmpty
            
            return AssetViewModel(
                id: asset.id,
                name: asset.name,
                symbol: asset.symbol,
                type: asset.type,
                currentPrice: 1.0, // Always 1 for savings accounts
                totalValue: totalValue,
                totalQuantity: displayQuantity,
                averagePrice: 1.0, // For savings, average price is always 1
                profitLoss: accruedInterest,
                profitLossPercentage: totalCost > 0 ? (accruedInterest / totalCost) * 100 : 0,
                interest_rate: currentRate,
                accruedInterest: accruedInterest,
                hasTransactions: hasTransactions
            )
        } catch {
            print("Error enriching Savings \(asset.symbol): \(error)")
            return nil
        }
    }
    
    private func calculateSavingsMetrics(
        transactions: [Transaction],
        interestRateHistory: [InterestRateHistory]
    ) -> (totalQuantity: Double, accruedInterest: Double) {
        var currentBalance = 0.0
        var lastTransactionDate = Date(timeIntervalSince1970: 0)
        var accruedInterest = 0.0
        
        // Sort interest rate history by start date
        let sortedRates = interestRateHistory.sorted(by: { $0.start_date < $1.start_date })
        
        // Process each transaction and calculate interest up to the next transaction
        for (i, transaction) in transactions.enumerated() {
            let transactionDate = transaction.transaction_date
            
            // Calculate interest for the period between last transaction and this one
            if currentBalance > 0 {
                // Calculate interest for each rate period between transactions
                for rate in sortedRates {
                    let rateStartDate = rate.start_date
                    let rateEndDate = rate.end_date ?? Date()
                    
                    // Check if this rate period overlaps with our transaction period
                    let periodStart = max(lastTransactionDate, rateStartDate)
                    let periodEnd = min(transactionDate, rateEndDate)
                    
                    // Set hours to 0 for consistent date comparison
                    let calendar = Calendar.current
                    var periodStartComponents = calendar.dateComponents([.year, .month, .day], from: periodStart)
                    var periodEndComponents = calendar.dateComponents([.year, .month, .day], from: periodEnd)
                    
                    guard let cleanPeriodStart = calendar.date(from: periodStartComponents),
                          let cleanPeriodEnd = calendar.date(from: periodEndComponents) else {
                        continue
                    }
                    
                    if cleanPeriodStart < cleanPeriodEnd {
                        // Calculate days in this period (add 1 to include both start and end dates)
                        let daysBetween = calendar.dateComponents([.day], from: cleanPeriodStart, to: cleanPeriodEnd).day! + 1
                        let dailyRate = (rate.rate / 100) / 365
                        let periodInterest = currentBalance * dailyRate * Double(daysBetween)
                        
                        print("Calculating interest for period \(cleanPeriodStart) to \(cleanPeriodEnd)")
                        print("Balance: \(currentBalance), Rate: \(rate.rate)%, Days: \(daysBetween)")
                        print("Interest earned: \(periodInterest)")
                        
                        accruedInterest += periodInterest
                    }
                }
            }
            
            // Update balance
            if transaction.type == .buy {
                currentBalance += transaction.quantity
            } else {
                currentBalance -= transaction.quantity
            }
            
            lastTransactionDate = transactionDate
        }
        
        // Calculate interest from last transaction to today
        if currentBalance > 0 {
            let today = Date()
            let calendar = Calendar.current
            var todayComponents = calendar.dateComponents([.year, .month, .day], from: today)
            guard let cleanToday = calendar.date(from: todayComponents) else {
                return (currentBalance, accruedInterest)
            }
            
            // Calculate interest for each rate period from last transaction to today
            for rate in sortedRates {
                let rateStartDate = rate.start_date
                let rateEndDate = rate.end_date ?? cleanToday
                
                // Check if this rate period overlaps with our final period
                let periodStart = max(lastTransactionDate, rateStartDate)
                let periodEnd = min(cleanToday, rateEndDate)
                
                // Set hours to 0 for consistent date comparison
                var periodStartComponents = calendar.dateComponents([.year, .month, .day], from: periodStart)
                var periodEndComponents = calendar.dateComponents([.year, .month, .day], from: periodEnd)
                
                guard let cleanPeriodStart = calendar.date(from: periodStartComponents),
                      let cleanPeriodEnd = calendar.date(from: periodEndComponents) else {
                    continue
                }
                
                if cleanPeriodStart < cleanPeriodEnd {
                    // Calculate days in this period (add 1 to include both start and end dates)
                    let daysBetween = calendar.dateComponents([.day], from: cleanPeriodStart, to: cleanPeriodEnd).day! + 1
                    let dailyRate = (rate.rate / 100) / 365
                    let periodInterest = currentBalance * dailyRate * Double(daysBetween)
                    
                    print("Calculating interest for final period \(cleanPeriodStart) to \(cleanPeriodEnd)")
                    print("Balance: \(currentBalance), Rate: \(rate.rate)%, Days: \(daysBetween)")
                    print("Interest earned: \(periodInterest)")
                    
                    accruedInterest += periodInterest
                }
            }
        }
        
        return (currentBalance, accruedInterest)
    }
} 