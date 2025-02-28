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

// MARK: - ETF Service
class ETFService: BaseAssetService, AssetServiceProtocol {
    private var priceCache: [String: (price: PriceData, timestamp: Date)] = [:]
    private let cacheDuration: TimeInterval = 20 // 20 seconds
    
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
            print("Error enriching ETF \(asset.symbol): \(error)")
            return nil
        }
    }
    
    private func getPrice(symbol: String) async throws -> PriceData {
        // Check cache
        if let cached = priceCache[symbol], 
           Date().timeIntervalSince(cached.timestamp) < cacheDuration {
            return cached.price
        }
        
        guard let rapidApiKey = ProcessInfo.processInfo.environment["RAPIDAPI_KEY"],
              !rapidApiKey.isEmpty else {
            throw NSError(domain: "ETFService", code: 1, userInfo: [NSLocalizedDescriptionKey: "RAPIDAPI_KEY environment variable is not set"])
        }
        
        // Handle different stock exchange suffixes
        let yahooSymbol = symbol.contains(".") ? symbol : "\(symbol).PA"
        
        let url = URL(string: "https://apidojo-yahoo-finance-v1.p.rapidapi.com/market/v2/get-quotes?region=FR&symbols=\(yahooSymbol)")!
        
        var request = URLRequest(url: url)
        request.addValue(rapidApiKey, forHTTPHeaderField: "x-rapidapi-key")
        request.addValue("apidojo-yahoo-finance-v1.p.rapidapi.com", forHTTPHeaderField: "x-rapidapi-host")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "ETFService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        
        if httpResponse.statusCode == 429 {
            throw NSError(domain: "ETFService", code: 429, userInfo: [NSLocalizedDescriptionKey: "RapidAPI rate limit exceeded. Please try again later."])
        }
        
        guard httpResponse.statusCode == 200 else {
            throw NSError(domain: "ETFService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "RapidAPI Yahoo Finance error: \(httpResponse.statusCode)"])
        }
        
        do {
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let quoteResponse = json?["quoteResponse"] as? [String: Any],
                  let results = quoteResponse["result"] as? [[String: Any]],
                  let result = results.first,
                  let price = result["regularMarketPrice"] as? Double else {
                throw NSError(domain: "ETFService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unexpected RapidAPI Yahoo Finance response format"])
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
            throw NSError(domain: "ETFService", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to parse response: \(error.localizedDescription)"])
        }
    }
}

// MARK: - Crypto Service
class CryptoService: BaseAssetService, AssetServiceProtocol {
    private var priceCache: [String: (price: PriceData, timestamp: Date)] = [:]
    private let cacheDuration: TimeInterval = 20 // 20 seconds
    
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
            print("Error enriching Crypto \(asset.symbol): \(error)")
            return nil
        }
    }
    
    private func getPrice(symbol: String) async throws -> PriceData {
        // Check cache
        if let cached = priceCache[symbol], 
           Date().timeIntervalSince(cached.timestamp) < cacheDuration {
            return cached.price
        }
        
        let url = URL(string: "https://api.coingecko.com/api/v3/simple/price?ids=bitcoin&vs_currencies=eur&include_24hr_change=true")!
        
        var request = URLRequest(url: url)
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "CryptoService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        
        if httpResponse.statusCode == 429 {
            throw NSError(domain: "CryptoService", code: 429, userInfo: [NSLocalizedDescriptionKey: "Rate limit exceeded. Please try again in a minute."])
        }
        
        guard httpResponse.statusCode == 200 else {
            throw NSError(domain: "CryptoService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "CoinGecko API error: \(httpResponse.statusCode)"])
        }
        
        do {
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let bitcoin = json?["bitcoin"] as? [String: Any],
                  let price = bitcoin["eur"] as? Double else {
                throw NSError(domain: "CryptoService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unexpected CoinGecko API response format"])
            }
            
            let priceData = PriceData(
                price: price,
                change24h: bitcoin["eur_24h_change"] as? Double
            )
            
            // Cache the result
            priceCache[symbol] = (priceData, Date())
            
            return priceData
        } catch {
            throw NSError(domain: "CryptoService", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to parse response: \(error.localizedDescription)"])
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
            
            let totalCost = calculateTotalCost(transactions: transactions)
            let totalValue = totalQuantity + accruedInterest
            
            return AssetViewModel(
                id: asset.id,
                name: asset.name,
                symbol: asset.symbol,
                type: asset.type,
                currentPrice: 1.0, // Always 1 for savings accounts
                totalValue: totalValue,
                totalQuantity: totalQuantity,
                averagePrice: totalQuantity > 0 ? totalCost / totalQuantity : 0,
                profitLoss: accruedInterest,
                profitLossPercentage: totalCost > 0 ? (accruedInterest / totalCost) * 100 : 0,
                interest_rate: currentRate,
                accruedInterest: accruedInterest
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