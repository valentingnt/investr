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
        
        // For assets with zero quantity but with transactions,
        // we need to calculate historical performance
        var profitLossPercentage: Double = 0
        
        if totalQuantity == 0 && !transactions.isEmpty {
            // Calculate the historical performance based on buy/sell transactions
            let totalBuyCost = transactions.filter { $0.type == .buy }
                .reduce(0) { $0 + $1.total_amount }
            
            let totalSellValue = transactions.filter { $0.type == .sell }
                .reduce(0) { $0 + $1.total_amount }
            
            // Calculate P&L for closed positions (completely sold assets)
            // We need to ensure buys and sells balance out (quantity = 0)
            let totalBoughtQuantity = transactions.filter { $0.type == .buy }
                .reduce(0) { $0 + $1.quantity }
            
            let totalSoldQuantity = transactions.filter { $0.type == .sell }
                .reduce(0) { $0 + $1.quantity }
                
            // Only calculate if quantities match (fully sold position) and there were buys
            if abs(totalBoughtQuantity - totalSoldQuantity) < 0.0001 && totalBuyCost > 0 {
                profitLossPercentage = ((totalSellValue - totalBuyCost) / totalBuyCost) * 100
                print("Closed position P&L for \(asset.name): Buy cost \(totalBuyCost), Sell value \(totalSellValue), P&L% \(profitLossPercentage)")
            }
        } else {
            // Normal case for assets with quantity
            let profitLoss = totalValue - totalCost
            profitLossPercentage = totalCost > 0 ? (profitLoss / totalCost) * 100 : 0
        }
        
        return AssetViewModel(
            id: asset.id,
            symbol: asset.symbol,
            name: asset.name,
            type: asset.type,
            quantity: totalQuantity,
            avgPurchasePrice: totalQuantity > 0 ? totalCost / totalQuantity : 0,
            currentPrice: price,
            totalValue: totalValue,
            percentChange: profitLossPercentage,
            transactions: transactions
        )
    }
} 