import Foundation

struct AssetViewModel: Identifiable, Hashable {
    let id: String
    let symbol: String
    let name: String
    let type: AssetType
    let quantity: Double
    let avgPurchasePrice: Double
    let currentPrice: Double
    let totalValue: Double
    let percentChange: Double
    let transactions: [Transaction]
    
    // Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: AssetViewModel, rhs: AssetViewModel) -> Bool {
        lhs.id == rhs.id
    }
    
    // Helper for creating from an Asset model
    static func fromAsset(_ asset: Asset, currentPrice: Double, transactions: [Transaction]) -> AssetViewModel {
        let buyTransactions = transactions.filter { $0.type == .buy }
        let sellTransactions = transactions.filter { $0.type == .sell }
        
        let totalBought = buyTransactions.reduce(0) { $0 + $1.quantity }
        let totalSold = sellTransactions.reduce(0) { $0 + $1.quantity }
        let quantity = totalBought - totalSold
        
        // Calculate average purchase price
        let totalCost = buyTransactions.reduce(0) { $0 + $1.total_amount }
        let avgPurchasePrice = totalBought > 0 ? totalCost / totalBought : 0
        
        // Calculate percent change
        let totalValue = quantity * currentPrice
        
        // Calculate performance
        var percentChange: Double = 0
        
        if quantity == 0 && !transactions.isEmpty {
            // For closed positions (quantity = 0), calculate historical performance
            let totalBuyCost = buyTransactions.reduce(0) { $0 + $1.total_amount }
            let totalSellValue = sellTransactions.reduce(0) { $0 + $1.total_amount }
            
            // Only calculate if the position was fully sold
            if totalBuyCost > 0 && abs(totalBought - totalSold) < 0.0001 {
                percentChange = ((totalSellValue - totalBuyCost) / totalBuyCost) * 100
            }
        } else {
            // For active positions, calculate based on current value vs cost
            percentChange = totalCost > 0 ? ((totalValue - totalCost) / totalCost) * 100 : 0
        }
        
        return AssetViewModel(
            id: asset.id,
            symbol: asset.symbol,
            name: asset.name,
            type: asset.type,
            quantity: quantity,
            avgPurchasePrice: avgPurchasePrice,
            currentPrice: currentPrice,
            totalValue: totalValue,
            percentChange: percentChange,
            transactions: transactions
        )
    }
}

// Helper for formatting
struct FormatHelper {
    static func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        formatter.groupingSeparator = " "
        
        return formatter.string(from: NSNumber(value: value)) ?? "0.00"
    }
    
    static func formatPercent(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        formatter.positivePrefix = "+"
        
        return (formatter.string(from: NSNumber(value: value)) ?? "0.00") + "%"
    }
    
    static func formatQuantity(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = value.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 6
        formatter.minimumFractionDigits = 0
        formatter.groupingSeparator = " "
        
        return formatter.string(from: NSNumber(value: value)) ?? "0"
    }
    
    static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        
        return formatter.string(from: date)
    }
} 