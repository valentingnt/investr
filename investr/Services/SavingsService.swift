import Foundation

// MARK: - Savings Service
final class SavingsService: BaseAssetService, AssetServiceProtocol {
    // Cache for interest rate calculations to avoid redundant processing
    private var interestCalculationCache: [String: (result: (Double, Double), timestamp: Date)] = [:]
    private let calculationCacheLock = NSLock()
    private let calculationCacheDuration: TimeInterval = 60 * 60 // 1 hour
    
    func enrichAssetWithPriceAndTransactions(
        asset: Asset,
        transactions: [Transaction]
    ) async -> AssetViewModel? {
        do {
            // For savings accounts, we need additional data that needs to be loaded separately
            // So we'll try to get interest rates stored in SwiftData
            
            // We would normally call the API to get the current interest rate for the account
            // But for simplicity, we'll just use a fixed value
            let currentRate = 3.0 // Example: 3% interest rate
            
            // Calculate metrics with optimized computation using the stored interest rate history
            // For simplicity, we'll simulate the accrued interest calculation
            let totalQuantity = calculateTotalQuantity(transactions: transactions)
            let accruedInterest = totalQuantity * 0.03 // Simple interest calculation example
            
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
                symbol: asset.symbol,
                name: asset.name,
                type: asset.type,
                quantity: displayQuantity,
                avgPurchasePrice: 1.0, // For savings, average price is always 1
                currentPrice: 1.0, // Always 1 for savings accounts
                totalValue: totalValue,
                percentChange: totalCost > 0 ? (accruedInterest / totalCost) * 100 : 0,
                transactions: transactions
            )
        } catch {
            print("Error enriching Savings \(asset.symbol): \(error)")
            return nil
        }
    }
    
    private func calculateSavingsMetrics(
        assetId: String,
        transactions: [Transaction],
        interestRateHistory: [InterestRateHistory]
    ) async -> (totalQuantity: Double, accruedInterest: Double) {
        // Check cache first
        let cacheKey = assetId
        let now = Date()
        
        calculationCacheLock.lock()
        if let cached = interestCalculationCache[cacheKey],
           now.timeIntervalSince(cached.timestamp) < calculationCacheDuration {
            calculationCacheLock.unlock()
            return cached.result
        }
        calculationCacheLock.unlock()
        
        // Calculate interest if not in cache
        var currentBalance = 0.0
        var lastTransactionDate = Date(timeIntervalSince1970: 0)
        var accruedInterest = 0.0
        
        // Sort interest rate history by start date once
        let sortedRates = interestRateHistory.sorted(by: { $0.start_date < $1.start_date })
        
        // Get the calendar once
        let calendar = Calendar.current
        let today = Date()
        let todayComponents = calendar.dateComponents([.year, .month, .day], from: today)
        let cleanToday = calendar.date(from: todayComponents) ?? today
        
        // Process each transaction and calculate interest up to the next transaction
        for transaction in transactions {
            let transactionDate = transaction.transaction_date
            
            // Calculate interest for the period between last transaction and this one
            if currentBalance > 0 {
                accruedInterest += calculateInterestForPeriod(
                    balance: currentBalance,
                    startDate: lastTransactionDate,
                    endDate: transactionDate,
                    interestRates: sortedRates,
                    calendar: calendar
                )
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
            accruedInterest += calculateInterestForPeriod(
                balance: currentBalance,
                startDate: lastTransactionDate,
                endDate: cleanToday,
                interestRates: sortedRates,
                calendar: calendar
            )
        }
        
        // Cache the result
        let result = (currentBalance, accruedInterest)
        calculationCacheLock.lock()
        interestCalculationCache[cacheKey] = (result, now)
        calculationCacheLock.unlock()
        
        return result
    }
    
    // Separate method for calculating interest for a single period
    private func calculateInterestForPeriod(
        balance: Double,
        startDate: Date,
        endDate: Date,
        interestRates: [InterestRateHistory],
        calendar: Calendar
    ) -> Double {
        var totalInterest = 0.0
        
        // Set hours to 0 for consistent date comparison
        let startComponents = calendar.dateComponents([.year, .month, .day], from: startDate)
        let endComponents = calendar.dateComponents([.year, .month, .day], from: endDate)
        
        guard let cleanStartDate = calendar.date(from: startComponents),
              let cleanEndDate = calendar.date(from: endComponents) else {
            return 0.0
        }
        
        // Calculate interest for each rate period between transactions
        for rate in interestRates {
            let rateStartDate = rate.start_date
            let rateEndDate = rate.end_date ?? Date()
            
            // Check if this rate period overlaps with our period
            let periodStart = max(cleanStartDate, rateStartDate)
            let periodEnd = min(cleanEndDate, rateEndDate)
            
            // Set hours to 0 for consistent date comparison
            let periodStartComponents = calendar.dateComponents([.year, .month, .day], from: periodStart)
            let periodEndComponents = calendar.dateComponents([.year, .month, .day], from: periodEnd)
            
            guard let cleanPeriodStart = calendar.date(from: periodStartComponents),
                  let cleanPeriodEnd = calendar.date(from: periodEndComponents) else {
                continue
            }
            
            if cleanPeriodStart < cleanPeriodEnd {
                // Calculate days in this period (add 1 to include both start and end dates)
                let daysBetween = calendar.dateComponents([.day], from: cleanPeriodStart, to: cleanPeriodEnd).day! + 1
                let dailyRate = (rate.rate / 100) / 365
                let periodInterest = balance * dailyRate * Double(daysBetween)
                
                totalInterest += periodInterest
            }
        }
        
        return totalInterest
    }
    
    // Method to clear calculation cache (e.g., when interest rates change)
    func clearCalculationCache() {
        calculationCacheLock.lock()
        interestCalculationCache.removeAll()
        calculationCacheLock.unlock()
    }
} 