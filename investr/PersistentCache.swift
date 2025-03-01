import Foundation
import UIKit

// MARK: - Persistent Cache
final class PersistentCache {
    static let shared = PersistentCache()
    
    private let userDefaults = UserDefaults.standard
    private let assetViewModelPrefix = "AssetViewModel_"
    private let assetTimestampPrefix = "AssetTimestamp_"
    
    // In-memory cache for faster access
    private var memoryCache: [String: AssetViewModel] = [:]
    private var memoryCacheLock = NSLock()
    
    // Cache duration in seconds
    private let cacheDuration: TimeInterval = 3 * 60 * 60 // 3 hours
    
    private init() {
        // Load frequently accessed data into memory cache at startup
        loadFrequentlyAccessedDataIntoMemory()
        
        // Register for memory warning notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clearMemoryCache),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func clearMemoryCache() {
        memoryCacheLock.lock()
        defer { memoryCacheLock.unlock() }
        
        memoryCache.removeAll()
    }
    
    private func loadFrequentlyAccessedDataIntoMemory() {
        // Find recently accessed assets and load them into memory
        let allKeys = userDefaults.dictionaryRepresentation().keys
        let timestampKeys = allKeys
            .filter { $0.hasPrefix(assetTimestampPrefix) }
            .sorted { 
                (userDefaults.object(forKey: $0) as? Date ?? Date.distantPast) >
                (userDefaults.object(forKey: $1) as? Date ?? Date.distantPast)
            }
            .prefix(5) // Load top 5 most recently accessed assets
        
        for key in timestampKeys {
            let assetId = String(key.dropFirst(assetTimestampPrefix.count))
            if let viewModel = retrieveAssetViewModel(for: assetId) {
                memoryCacheLock.lock()
                memoryCache[assetId] = viewModel
                memoryCacheLock.unlock()
            }
        }
    }
    
    func saveAssetViewModel(_ viewModel: AssetViewModel) {
        // Store individual properties to UserDefaults
        storeAssetViewModelProperties(viewModel)
        
        // Update memory cache
        memoryCacheLock.lock()
        memoryCache[viewModel.id] = viewModel
        memoryCacheLock.unlock()
    }
    
    func getAssetViewModel(for assetId: String) -> AssetViewModel? {
        // Try memory cache first for better performance
        memoryCacheLock.lock()
        if let cachedViewModel = memoryCache[assetId] {
            memoryCacheLock.unlock()
            return cachedViewModel
        }
        memoryCacheLock.unlock()
        
        // Fall back to disk cache
        guard let viewModel = retrieveAssetViewModel(for: assetId) else { return nil }
        
        // Update memory cache with fetched data
        memoryCacheLock.lock()
        memoryCache[assetId] = viewModel
        memoryCacheLock.unlock()
        
        return viewModel
    }
    
    func isCacheExpired(for assetId: String) -> Bool {
        guard let timestamp = userDefaults.object(forKey: assetTimestampPrefix + assetId) as? Date else {
            return true
        }
        
        return Date().timeIntervalSince(timestamp) > cacheDuration
    }
    
    func clearCacheTimestamps() {
        // Find all cache timestamps and remove them
        let allKeys = userDefaults.dictionaryRepresentation().keys
        let timestampKeys = allKeys.filter { $0.hasPrefix(assetTimestampPrefix) }
        
        for key in timestampKeys {
            userDefaults.removeObject(forKey: key)
        }
        
        // Clear memory cache as well
        clearMemoryCache()
    }
    
    func clearAllCache() {
        // Find all cache data and timestamps and remove them
        let allKeys = userDefaults.dictionaryRepresentation().keys
        let cacheKeys = allKeys.filter { $0.hasPrefix(assetViewModelPrefix) || $0.hasPrefix(assetTimestampPrefix) }
        
        for key in cacheKeys {
            userDefaults.removeObject(forKey: key)
        }
        
        // Clear memory cache
        clearMemoryCache()
    }
    
    // MARK: - Manual Encoding/Decoding for AssetViewModel
    
    private func storeAssetViewModelProperties(_ viewModel: AssetViewModel) {
        let keyPrefix = assetViewModelPrefix + viewModel.id + "."
        
        userDefaults.set(viewModel.id, forKey: keyPrefix + "id")
        userDefaults.set(viewModel.name, forKey: keyPrefix + "name")
        userDefaults.set(viewModel.symbol, forKey: keyPrefix + "symbol")
        userDefaults.set(viewModel.type.rawValue, forKey: keyPrefix + "type")
        userDefaults.set(viewModel.currentPrice, forKey: keyPrefix + "currentPrice")
        userDefaults.set(viewModel.totalValue, forKey: keyPrefix + "totalValue")
        userDefaults.set(viewModel.totalQuantity, forKey: keyPrefix + "totalQuantity")
        userDefaults.set(viewModel.averagePrice, forKey: keyPrefix + "averagePrice")
        userDefaults.set(viewModel.profitLoss, forKey: keyPrefix + "profitLoss")
        userDefaults.set(viewModel.profitLossPercentage, forKey: keyPrefix + "profitLossPercentage")
        
        // Optional fields
        if let change24h = viewModel.change24h {
            userDefaults.set(change24h, forKey: keyPrefix + "change24h")
        }
        if let dayHigh = viewModel.dayHigh {
            userDefaults.set(dayHigh, forKey: keyPrefix + "dayHigh")
        }
        if let dayLow = viewModel.dayLow {
            userDefaults.set(dayLow, forKey: keyPrefix + "dayLow")
        }
        if let previousClose = viewModel.previousClose {
            userDefaults.set(previousClose, forKey: keyPrefix + "previousClose")
        }
        if let volume = viewModel.volume {
            userDefaults.set(volume, forKey: keyPrefix + "volume")
        }
        if let interestRate = viewModel.interest_rate {
            userDefaults.set(interestRate, forKey: keyPrefix + "interest_rate")
        }
        if let accruedInterest = viewModel.accruedInterest {
            userDefaults.set(accruedInterest, forKey: keyPrefix + "accruedInterest")
        }
        userDefaults.set(viewModel.hasTransactions, forKey: keyPrefix + "hasTransactions")
        
        // Set timestamp
        userDefaults.set(Date(), forKey: assetTimestampPrefix + viewModel.id)
    }
    
    private func retrieveAssetViewModel(for assetId: String) -> AssetViewModel? {
        let keyPrefix = assetViewModelPrefix + assetId + "."
        
        // Check if any data exists for this asset
        guard let id = userDefaults.string(forKey: keyPrefix + "id") else {
            return nil
        }
        
        guard let name = userDefaults.string(forKey: keyPrefix + "name"),
              let symbol = userDefaults.string(forKey: keyPrefix + "symbol"),
              let typeRawValue = userDefaults.string(forKey: keyPrefix + "type"),
              let type = AssetType(rawValue: typeRawValue) else {
            return nil
        }
        
        let currentPrice = userDefaults.double(forKey: keyPrefix + "currentPrice")
        let totalValue = userDefaults.double(forKey: keyPrefix + "totalValue")
        let totalQuantity = userDefaults.double(forKey: keyPrefix + "totalQuantity")
        let averagePrice = userDefaults.double(forKey: keyPrefix + "averagePrice")
        let profitLoss = userDefaults.double(forKey: keyPrefix + "profitLoss")
        let profitLossPercentage = userDefaults.double(forKey: keyPrefix + "profitLossPercentage")
        
        // Create view model
        var viewModel = AssetViewModel(
            id: id,
            name: name,
            symbol: symbol,
            type: type,
            currentPrice: currentPrice,
            totalValue: totalValue,
            totalQuantity: totalQuantity,
            averagePrice: averagePrice,
            profitLoss: profitLoss,
            profitLossPercentage: profitLossPercentage
        )
        
        // Optional fields
        if userDefaults.object(forKey: keyPrefix + "change24h") != nil {
            viewModel.change24h = userDefaults.double(forKey: keyPrefix + "change24h")
        }
        if userDefaults.object(forKey: keyPrefix + "dayHigh") != nil {
            viewModel.dayHigh = userDefaults.double(forKey: keyPrefix + "dayHigh")
        }
        if userDefaults.object(forKey: keyPrefix + "dayLow") != nil {
            viewModel.dayLow = userDefaults.double(forKey: keyPrefix + "dayLow")
        }
        if userDefaults.object(forKey: keyPrefix + "previousClose") != nil {
            viewModel.previousClose = userDefaults.double(forKey: keyPrefix + "previousClose")
        }
        if userDefaults.object(forKey: keyPrefix + "volume") != nil {
            viewModel.volume = userDefaults.double(forKey: keyPrefix + "volume")
        }
        if userDefaults.object(forKey: keyPrefix + "interest_rate") != nil {
            viewModel.interest_rate = userDefaults.double(forKey: keyPrefix + "interest_rate")
        }
        if userDefaults.object(forKey: keyPrefix + "accruedInterest") != nil {
            viewModel.accruedInterest = userDefaults.double(forKey: keyPrefix + "accruedInterest")
        }
        viewModel.hasTransactions = userDefaults.bool(forKey: keyPrefix + "hasTransactions")
        
        return viewModel
    }
} 