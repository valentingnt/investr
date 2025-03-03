import Foundation

// MARK: - API Key Manager
final class APIKeyManager {
    static let shared = APIKeyManager()
    
    private init() {}
    
    // Keys in UserDefaults and Plist file
    enum APIKeyType: String, CaseIterable {
        case cryptocompare = "CRYPTOCOMPARE_API_KEY"
        case coingecko = "COINGECKO_API_KEY"
        case rapidapi = "RAPIDAPI_KEY"
        case financialModelingPrep = "FMP_API_KEY"
        case alphavantage = "ALPHAVANTAGE_API_KEY"
        case coinapi = "COINAPI_KEY"
        case twelvedata = "TWELVEDATA_API_KEY"
    }
    
    // Get API key from multiple sources
    func getAPIKey(_ type: APIKeyType) -> String {
        // First check UserDefaults
        if let key = UserDefaults.standard.string(forKey: type.rawValue),
           !key.isEmpty {
            return key
        }
        
        // Then check ConfigurationManager
        if type == .rapidapi {
            let rapidAPIKey = ConfigurationManager.shared.rapidAPIKey
            if ConfigurationManager.shared.isValidAPIKey(rapidAPIKey) {
                return rapidAPIKey
            }
        } else {
            // Try to get from ConfigurationManager's dictionary
            if let key = ConfigurationManager.shared.string(for: type.rawValue),
               !key.isEmpty,
               !key.contains("YOUR_") {
                return key
            }
        }
        
        return ""
    }
    
    // Save API key to UserDefaults
    func saveAPIKey(_ type: APIKeyType, value: String) {
        UserDefaults.standard.set(value, forKey: type.rawValue)
    }
    
    // Check if an API key exists and is valid
    func hasValidAPIKey(_ type: APIKeyType) -> Bool {
        let key = getAPIKey(type)
        return !key.isEmpty && !key.contains("YOUR_")
    }
    
    // Get all valid API keys
    func getAllValidAPIKeys() -> [APIKeyType: String] {
        var result = [APIKeyType: String]()
        
        for keyType in [
            APIKeyType.cryptocompare,
            .coingecko,
            .rapidapi,
            .financialModelingPrep,
            .alphavantage,
            .coinapi,
            .twelvedata
        ] {
            if hasValidAPIKey(keyType) {
                result[keyType] = getAPIKey(keyType)
            }
        }
        
        return result
    }
    
    // Get available crypto providers
    func getAvailableCryptoProviders() -> [String] {
        var providers = [String]()
        
        if hasValidAPIKey(.cryptocompare) {
            providers.append("CryptoCompare")
        }
        
        if hasValidAPIKey(.coingecko) || hasValidAPIKey(.rapidapi) {
            providers.append("CoinGecko")
        }
        
        if hasValidAPIKey(.coinapi) {
            providers.append("CoinAPI")
        }
        
        return providers
    }
    
    // Get available ETF providers
    func getAvailableETFProviders() -> [String] {
        var providers = [String]()
        
        if hasValidAPIKey(.financialModelingPrep) {
            providers.append("Financial Modeling Prep")
        }
        
        if hasValidAPIKey(.alphavantage) {
            providers.append("Alpha Vantage")
        }
        
        if hasValidAPIKey(.twelvedata) {
            providers.append("TwelveData")
        }
        
        return providers
    }
} 