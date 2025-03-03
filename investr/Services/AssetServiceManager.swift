import Foundation
import UIKit

// MARK: - Asset Service Manager
final class AssetServiceManager {
    static let shared = AssetServiceManager()
    
    private let etfService = ETFService()
    private let cryptoService = CryptoService()
    private let savingsService = SavingsService()
    
    /// Dictionary to track whether an asset's price data is currently being refreshed
    private var refreshingAssets: [String: Bool] = [:]
    /// Lock for thread-safe access to refreshingAssets
    private let refreshingAssetsLock = NSLock()
    
    /// Flag to indicate if this is the first launch of the app
    private var isFirstLaunch: Bool = UserDefaults.standard.object(forKey: "AssetServiceManager.launchedBefore") == nil
    
    // Dictionary of update callbacks by asset ID
    private var updateCallbacks: [String: [(AssetViewModel) -> Void]] = [:]
    /// Lock for thread-safe access to updateCallbacks
    private let updateCallbacksLock = NSLock()
    
    // Notification name for asset updates
    static let assetUpdatedNotification = Notification.Name("AssetUpdatedNotification")
    
    // Task manager to handle background tasks
    private var pendingUpdateTasks: [String: Task<Void, Never>] = [:]
    private let pendingTasksLock = NSLock()
    
    private init() {
        if isFirstLaunch {
            UserDefaults.standard.set(true, forKey: "AssetServiceManager.launchedBefore")
        }
        
        // Set up notification handling for app entering background/foreground
        NotificationCenter.default.addObserver(
            self, 
            selector: #selector(appWillEnterBackground),
            name: UIApplication.willResignActiveNotification, 
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self, 
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification, 
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func appWillEnterBackground() {
        // Cancel pending tasks when app enters background
        cancelAllPendingTasks()
    }
    
    @objc private func appWillEnterForeground() {
        // Refresh data for active assets when app returns to foreground
        refreshAllActiveAssets()
    }
    
    private func cancelAllPendingTasks() {
        pendingTasksLock.lock()
        defer { pendingTasksLock.unlock() }
        
        for (_, task) in pendingUpdateTasks {
            task.cancel()
        }
        pendingUpdateTasks.removeAll()
    }
    
    private func refreshAllActiveAssets() {
        // This would be called when app returns to foreground
        // Get list of active assets from cache and refresh them
        PersistentCache.shared.clearCacheTimestamps()
    }
    
    /// Creates a basic view model with default values that can be displayed immediately
    func createBasicViewModel(asset: Asset) -> AssetViewModel {
        // Try to get cached data first
        if let cachedViewModel = PersistentCache.shared.getAssetViewModel(for: asset.id) {
            return cachedViewModel
        }
        
        // Otherwise create a placeholder with minimal data
        return AssetViewModel(
            id: asset.id,
            symbol: asset.symbol,
            name: asset.name,
            type: asset.type,
            quantity: 0.0,
            avgPurchasePrice: 0.0,
            currentPrice: 0.0,
            totalValue: 0.0,
            percentChange: 0.0,
            transactions: []
        )
    }
    
    /// Schedules the asset for background enrichment and returns immediately with a basic view model
    func getAssetViewModel(
        asset: Asset,
        transactions: [Transaction],
        forceRefresh: Bool = false,
        interestRateHistory: [InterestRateHistory]? = nil,
        supabaseManager: SupabaseManager? = nil,
        onUpdate: ((AssetViewModel) -> Void)? = nil
    ) -> AssetViewModel {
        // Step 1: Create and return a basic view model immediately
        let baseViewModel = createBasicViewModel(asset: asset)
        
        // Register the update callback if provided
        if let onUpdate = onUpdate {
            registerCallback(for: asset.id, callback: onUpdate)
        }
        
        // Cancel any existing task for this asset
        cancelUpdateTask(for: asset.id)
        
        // Step 2: Schedule the asset for enrichment in the background
        let task = Task {
            if let enrichedViewModel = await self.enrichAsset(
                asset: asset, 
                transactions: transactions,
                forceRefresh: forceRefresh,
                interestRateHistory: interestRateHistory,
                supabaseManager: supabaseManager
            ) {
                // Step 3: Notify listeners when data is updated
                await MainActor.run {
                    // Trigger all callbacks registered for this asset
                    notifyCallbacks(for: asset.id, with: enrichedViewModel)
                    
                    // Post a notification that can be observed by any interested parties
                    NotificationCenter.default.post(
                        name: AssetServiceManager.assetUpdatedNotification,
                        object: nil,
                        userInfo: ["assetId": asset.id, "viewModel": enrichedViewModel]
                    )
                }
            }
        }
        
        // Store the task
        pendingTasksLock.lock()
        pendingUpdateTasks[asset.id] = task
        pendingTasksLock.unlock()
        
        return baseViewModel
    }
    
    // Register a callback for asset updates
    private func registerCallback(for assetId: String, callback: @escaping (AssetViewModel) -> Void) {
        updateCallbacksLock.lock()
        defer { updateCallbacksLock.unlock() }
        
        if updateCallbacks[assetId] == nil {
            updateCallbacks[assetId] = []
        }
        updateCallbacks[assetId]?.append(callback)
    }
    
    // Notify all callbacks for an asset
    private func notifyCallbacks(for assetId: String, with viewModel: AssetViewModel) {
        updateCallbacksLock.lock()
        let callbacks = updateCallbacks[assetId] ?? []
        updateCallbacksLock.unlock()
        
        for callback in callbacks {
            // Ensure the callback is always executed on the main thread
            if Thread.isMainThread {
                callback(viewModel)
            } else {
                DispatchQueue.main.async {
                    callback(viewModel)
                }
            }
        }
    }
    
    // Cancel update task for an asset
    private func cancelUpdateTask(for assetId: String) {
        pendingTasksLock.lock()
        defer { pendingTasksLock.unlock() }
        
        if let existingTask = pendingUpdateTasks[assetId] {
            existingTask.cancel()
            pendingUpdateTasks[assetId] = nil
        }
    }
    
    /// The main enrichment function that fetches data from APIs
    func enrichAsset(
        asset: Asset,
        transactions: [Transaction],
        forceRefresh: Bool = false,
        interestRateHistory: [InterestRateHistory]? = nil,
        supabaseManager: SupabaseManager? = nil
    ) async -> AssetViewModel? {
        // Generate a unique key for this asset
        let assetKey = "\(asset.type.rawValue)_\(asset.id)"
        
        // Thread-safe check if we're already refreshing this asset
        refreshingAssetsLock.lock()
        let isAlreadyRefreshing = refreshingAssets[assetKey] == true
        if !isAlreadyRefreshing {
            refreshingAssets[assetKey] = true
        }
        refreshingAssetsLock.unlock()
        
        if isAlreadyRefreshing {
            // Return cached data if available, otherwise wait for the refresh to complete
            if let cachedViewModel = PersistentCache.shared.getAssetViewModel(for: asset.id) {
                return cachedViewModel
            }
            return nil
        }
        
        // Use defer to ensure we clear the flag even if there's an error
        defer {
            refreshingAssetsLock.lock()
            refreshingAssets[assetKey] = false
            refreshingAssetsLock.unlock()
        }
        
        // Check if we should use cached data
        if !forceRefresh && !isFirstLaunch {
            if let cachedViewModel = PersistentCache.shared.getAssetViewModel(for: asset.id) {
                if !PersistentCache.shared.isCacheExpired(for: asset.id) {
                    return cachedViewModel
                }
            }
        }
        
        // Get fresh data based on asset type
        let viewModel: AssetViewModel?
        
        switch asset.type {
        case .etf:
            viewModel = await etfService.enrichAssetWithPriceAndTransactions(
                asset: asset,
                transactions: transactions
            )
        case .crypto:
            viewModel = await cryptoService.enrichAssetWithPriceAndTransactions(
                asset: asset,
                transactions: transactions
            )
        case .savings:
            viewModel = await savingsService.enrichAssetWithPriceAndTransactions(
                asset: asset,
                transactions: transactions
            )
        }
        
        // Cache the result if we got valid data
        if let viewModel = viewModel {
            PersistentCache.shared.saveAssetViewModel(viewModel)
        }
        
        return viewModel
    }
    
    func refreshAllAssets() {
        // Clears cache flags to force refreshing
        PersistentCache.shared.clearCacheTimestamps()
    }
    
    /// Register a callback to be notified when an asset is updated
    func registerForUpdates(assetId: String, callback: @escaping (AssetViewModel) -> Void) {
        updateCallbacksLock.lock()
        defer { updateCallbacksLock.unlock() }
        
        if updateCallbacks[assetId] == nil {
            updateCallbacks[assetId] = []
        }
        updateCallbacks[assetId]?.append(callback)
    }
    
    /// Unregister all callbacks for an asset
    func unregisterForUpdates(assetId: String) {
        updateCallbacksLock.lock()
        defer { updateCallbacksLock.unlock() }
        
        updateCallbacks[assetId] = nil
    }
    
    /// Cancel update tasks for specific assets
    func cancelUpdate(for assetId: String) {
        cancelUpdateTask(for: assetId)
    }
} 