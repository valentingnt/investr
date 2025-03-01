import Foundation

// MARK: - Asset Service Protocol
protocol AssetServiceProtocol {
    func enrichAssetWithPriceAndTransactions(
        asset: Asset,
        transactions: [Transaction]
    ) async -> AssetViewModel?
}

// MARK: - Base Asset Service
class BaseAssetService {
    // Calculate basic metrics from transactions
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
    
    // Create a view model with price data and transaction data
    func createBaseViewModel(
        asset: Asset,
        priceData: PriceData?,
        transactions: [Transaction]
    ) -> AssetViewModel {
        let totalQuantity = calculateTotalQuantity(transactions: transactions)
        let totalCost = calculateTotalCost(transactions: transactions)
        
        let price = priceData?.price ?? 0.0
        let totalValue = totalQuantity * price
        
        // Only calculate these if we have valid data to avoid NaN or infinite values
        let profitLoss = totalValue - totalCost
        let profitLossPercentage = totalCost > 0 ? ((totalValue - totalCost) / totalCost) * 100 : 0
        
        return AssetViewModel(
            id: asset.id,
            name: asset.name,
            symbol: asset.symbol,
            type: asset.type,
            currentPrice: price,
            totalValue: totalValue,
            totalQuantity: totalQuantity,
            averagePrice: totalQuantity > 0 ? totalCost / totalQuantity : 0,
            profitLoss: profitLoss,
            profitLossPercentage: profitLossPercentage,
            change24h: priceData?.change24h,
            dayHigh: priceData?.dayHigh,
            dayLow: priceData?.dayLow,
            previousClose: priceData?.previousClose,
            volume: priceData?.volume
        )
    }
} 