import Foundation

// MARK: - ETF Service
final class ETFService: BaseAssetService, AssetServiceProtocol {
    // Use the APIManager for better API management
    private let apiManager = APIManager.shared
    
    func enrichAssetWithPriceAndTransactions(
        asset: Asset,
        transactions: [Transaction]
    ) async -> AssetViewModel? {
        do {
            print("ETFService: Getting price for \(asset.symbol)")
            let priceData = try await fetchPrice(symbol: asset.symbol)
            return createBaseViewModel(asset: asset, priceData: priceData, transactions: transactions)
        } catch {
            print("⚠️ ETFService error for \(asset.symbol): \(error.localizedDescription)")
            
            // Don't use fallback data, instead create a model with 0 price
            // This ensures we still have the asset in the UI but without fake data
            let emptyPriceData = PriceData(price: 0, change24h: 0)
            return createBaseViewModel(asset: asset, priceData: emptyPriceData, transactions: transactions)
        }
    }
    
    private func fetchPrice(symbol: String) async throws -> PriceData {
        // Use the APIManager to handle multiple providers with failover
        return try await apiManager.fetchETFPriceData(symbol: symbol)
    }
} 