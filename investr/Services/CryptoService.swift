import Foundation

// MARK: - Crypto Service
final class CryptoService: BaseAssetService, AssetServiceProtocol {
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
    
    // Use the APIManager for better API management
    private let apiManager = APIManager.shared
    
    func enrichAssetWithPriceAndTransactions(
        asset: Asset,
        transactions: [Transaction]
    ) async -> AssetViewModel? {
        do {
            print("CryptoService: Getting price for \(asset.symbol)")
            let priceData = try await fetchPrice(symbol: asset.symbol)
            return createBaseViewModel(asset: asset, priceData: priceData, transactions: transactions)
        } catch {
            print("⚠️ CryptoService error for \(asset.symbol): \(error.localizedDescription)")
            
            // Try fallback data if available
            if let fallback = emergencyPriceData[asset.symbol] {
                print("Using fallback data for \(asset.symbol)")
                return createBaseViewModel(asset: asset, priceData: fallback, transactions: transactions)
            }
            
            // Return a basic model with no price data
            return createBaseViewModel(asset: asset, priceData: nil, transactions: transactions)
        }
    }
    
    private func fetchPrice(symbol: String) async throws -> PriceData {
        // Use the APIManager to handle multiple providers with failover
        return try await apiManager.fetchCryptoPriceData(symbol: symbol)
    }
}