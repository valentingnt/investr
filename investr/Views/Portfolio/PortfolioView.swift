import SwiftUI
import SwiftData

struct PortfolioView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var supabaseManager: SupabaseManager
    
    @Query private var assets: [Asset]
    @Query private var transactions: [Transaction]
    
    @State private var isLoading = false
    @State private var isRefreshing = false
    @State private var portfolioValue: Double = 0
    @State private var portfolioItems: [AssetViewModel] = []
    @State private var showingAddAsset = false
    @State private var isLoadingInProgress = false
    @State private var refreshTask: Task<Void, Never>?
    @Namespace private var namespace
    
    // Display preference for performance values (percentage vs numeric)
    @AppStorage("displayPerformanceAsPercentage") private var displayPerformanceAsPercentage: Bool = true
    
    var body: some View {
        NavigationStack {
            PortfolioAssetsListView(
                portfolioItems: portfolioItems,
                portfolioValue: portfolioValue,
                isLoading: isLoading,
                isRefreshing: isRefreshing,
                namespace: namespace,
                displayPerformanceAsPercentage: $displayPerformanceAsPercentage
            )
            .navigationTitle("Portfolio")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingAddAsset = true
                    }) {
                        Image(systemName: "plus")
                            .foregroundColor(Theme.Colors.primaryText)
                            .symbolEffect(.pulse, isActive: isLoading)
                    }
                }
            }
            .sheet(isPresented: $showingAddAsset) {
                AddAssetView() {
                    Task {
                        // Force a reload when an asset is added
                        print("Asset added - refreshing portfolio view")
                        portfolioItems = [] // Clear to force a rebuild
                        await loadAssetsIndependently()
                    }
                }
                .environmentObject(supabaseManager)
            }
            .refreshable {
                await loadData()
            }
            .animation(.smooth, value: portfolioItems)
        }
        .task {
            // Initial data load when the view appears
            await loadData()
        }
        .onChange(of: assets.count) { oldCount, newCount in
            if oldCount != newCount {
                print("Asset count changed in PortfolioView: \(oldCount) to \(newCount)")
                Task {
                    // Reload when assets change
                    portfolioItems = [] // Clear to force a rebuild
                    await loadAssetsIndependently()
                }
            }
        }
        .onChange(of: transactions.count) { oldCount, newCount in
            if oldCount != newCount {
                print("Transaction count changed in PortfolioView: \(oldCount) to \(newCount)")
                Task {
                    // Reload assets with updated data
                    await loadAssetsIndependently()
                }
            }
        }
    }
    
    // MARK: - Data Loading Functions
    
    private func loadData() async {
        // Cancel any existing refresh task
        print("Starting complete data refresh including API calls")
        isLoading = true
        isRefreshing = true
        
        // Cancel any existing refresh task
        refreshTask?.cancel()
        
        refreshTask = Task {
            do {
                // Fetch assets and transactions from Supabase API
                print("Starting to fetch data from API...")
                
                // Fetch and save assets - requesting fresh data from server
                print("Fetching assets from API...")
                let assetResponses = try await supabaseManager.fetchAssets()
                print("Successfully fetched \(assetResponses.count) assets from API")
                
                // Fetch and save transactions - requesting fresh data from server
                print("Fetching transactions from API...")
                let transactionResponses = try await supabaseManager.fetchTransactions()
                print("Successfully fetched \(transactionResponses.count) transactions from API")
                
                // Update local SwiftData models
                await MainActor.run {
                    print("Updating local SwiftData models...")
                    
                    // Create set of asset IDs from the response
                    let apiAssetIds = Set(assetResponses.map { $0.id })
                    
                    // Remove assets that no longer exist in Supabase
                    for asset in assets {
                        if !apiAssetIds.contains(asset.id) {
                            print("Deleting asset that no longer exists on server: \(asset.name) (\(asset.id))")
                            modelContext.delete(asset)
                        }
                    }
                    
                    // Update assets
                    for assetResponse in assetResponses {
                        // Check if asset already exists in SwiftData
                        if let existingAsset = assets.first(where: { $0.id == assetResponse.id }) {
                            // Update existing asset
                            existingAsset.symbol = assetResponse.symbol
                            existingAsset.name = assetResponse.name
                            existingAsset.isin = assetResponse.isin
                            existingAsset.type = AssetType(rawValue: assetResponse.type) ?? .etf
                            existingAsset.updated_at = Date()
                            print("Updated existing asset: \(existingAsset.name)")
                        } else {
                            // Create new asset
                            let newAsset = assetResponse.toAsset()
                            modelContext.insert(newAsset)
                            print("Inserted new asset: \(newAsset.name)")
                        }
                    }
                    
                    // Create set of transaction IDs from the response
                    let apiTransactionIds = Set(transactionResponses.map { $0.id })
                    
                    // Remove transactions that no longer exist in Supabase
                    for transaction in transactions {
                        if !apiTransactionIds.contains(transaction.id) {
                            print("Deleting transaction that no longer exists on server: \(transaction.id)")
                            modelContext.delete(transaction)
                        }
                    }
                    
                    // Update transactions
                    for transactionResponse in transactionResponses {
                        // Check if transaction already exists in SwiftData
                        if let existingTransaction = transactions.first(where: { $0.id == transactionResponse.id }) {
                            // Delete the existing transaction to avoid conflicts
                            // This is a simple approach to ensure we always have the latest data
                            modelContext.delete(existingTransaction)
                            print("Deleted existing transaction: \(existingTransaction.id)")
                        }
                        
                        // Create new transaction with proper dates
                        let newTransaction = transactionResponse.toTransaction()
                        
                        // Set asset relationship
                        if let asset = assets.first(where: { $0.id == newTransaction.asset_id }) {
                            newTransaction.asset = asset
                            print("Set asset relationship for transaction: \(newTransaction.id) to asset: \(asset.name)")
                        } else {
                            print("Warning: Couldn't find asset with ID \(newTransaction.asset_id) for transaction")
                        }
                        
                        modelContext.insert(newTransaction)
                        print("Inserted transaction: \(newTransaction.id)")
                    }
                    
                    // Save changes
                    do {
                        try modelContext.save()
                        print("Successfully saved all changes to SwiftData")
                    } catch {
                        print("Error saving changes to SwiftData: \(error)")
                    }
                }
                
                // Reset portfolioItems to force a complete rebuild with fresh data
                await MainActor.run {
                    portfolioItems = []
                }
                
                // Load assets with updated data
                await loadAssetsIndependently()
                
                await MainActor.run {
                    // Update the UI on the main thread
                    withAnimation(.smooth) {
                        isLoading = false
                        isRefreshing = false
                    }
                }
            } catch {
                print("Error loading data: \(error.localizedDescription)")
                await MainActor.run {
                    isLoading = false
                    isRefreshing = false
                }
            }
        }
    }
    
    // Add a helper method to convert Transaction to TransactionViewModel
    private func convertToTransactionViewModel(transaction: Transaction) -> TransactionViewModel {
        return TransactionViewModel(
            id: transaction.id,
            assetId: transaction.asset_id,
            assetName: transaction.asset?.name ?? "Unknown Asset",
            type: transaction.type,
            quantity: transaction.quantity,
            price: transaction.price_per_unit,
            totalAmount: transaction.total_amount,
            date: transaction.transaction_date
        )
    }
    
    // Helper function to calculate performance considering both active and closed positions
    private func calculatePerformance(totalQuantity: Double, totalCost: Double, currentPrice: Double, transactions: [Transaction]) -> Double {
        // For closed positions (quantity = 0), calculate historical performance
        if totalQuantity == 0 && !transactions.isEmpty {
            let buyTransactions = transactions.filter { $0.type == .buy }
            let sellTransactions = transactions.filter { $0.type == .sell }
            
            let totalBuyCost = buyTransactions.reduce(0) { $0 + $1.total_amount }
            let totalSellValue = sellTransactions.reduce(0) { $0 + $1.total_amount }
            
            let totalBoughtQuantity = buyTransactions.reduce(0) { $0 + $1.quantity }
            let totalSoldQuantity = sellTransactions.reduce(0) { $0 + $1.quantity }
            
            // Only calculate if we have a fully closed position
            if totalBuyCost > 0 && abs(totalBoughtQuantity - totalSoldQuantity) < 0.0001 {
                return ((totalSellValue - totalBuyCost) / totalBuyCost) * 100
            }
            return 0
        } else {
            // For active positions, calculate based on current value vs cost
            let totalValue = totalQuantity * currentPrice
            return totalCost > 0 ? ((totalValue - totalCost) / totalCost) * 100 : 0
        }
    }
    
    private func loadAssetsIndependently() async {
        // Create new list for portfolio items
        var totalPortfolioValue: Double = 0
        
        print("Starting to load \(assets.count) assets independently")
        
        // First, immediately create a basic view model for each asset without waiting for API data
        await MainActor.run {
            // Clear existing items if they're passed as empty
            if portfolioItems.isEmpty {
                print("Building fresh portfolio items list from scratch")
                for asset in assets {
                    // Get transactions for this specific asset
                    let assetTransactions = transactions.filter { $0.asset_id == asset.id }
                    
                    // Convert the transactions to view models for display
                    let transactionViewModels = assetTransactions.map { convertToTransactionViewModel(transaction: $0) }
                    
                    // Get a basic view model with minimal data
                    var baseViewModel = AssetServiceManager.shared.createBasicViewModel(asset: asset)
                    
                    // Calculate basic metrics that don't need API calls
                    let service = BaseAssetService()
                    let totalQuantity = service.calculateTotalQuantity(transactions: assetTransactions)
                    let totalCost = service.calculateTotalCost(transactions: assetTransactions)
                    
                    // Create a new view model with the updated values instead of modifying properties
                    let updatedViewModel = AssetViewModel(
                        id: baseViewModel.id,
                        symbol: baseViewModel.symbol,
                        name: baseViewModel.name,
                        type: baseViewModel.type,
                        quantity: totalQuantity,
                        avgPurchasePrice: totalQuantity > 0 ? totalCost / totalQuantity : 0,
                        currentPrice: baseViewModel.currentPrice,
                        totalValue: baseViewModel.currentPrice * totalQuantity,
                        percentChange: calculatePerformance(totalQuantity: totalQuantity, totalCost: totalCost, currentPrice: baseViewModel.currentPrice, transactions: assetTransactions),
                        transactions: assetTransactions
                    )
                    
                    // Always add assets to the portfolio items, even if they don't have transactions yet
                    // This ensures newly added assets appear immediately
                    portfolioItems.append(updatedViewModel)
                }
            } else {
                print("Updating existing portfolio items")
            }
        }
        
        // Then, start background enrichment for each asset
        for asset in assets {
            // Skip if the task was cancelled
            if Task.isCancelled { 
                print("Task was cancelled, stopping asset loading")
                break 
            }
            
            // Get transactions for this specific asset
            let assetTransactions = transactions.filter { $0.asset_id == asset.id }
            print("Enriching asset: \(asset.name) (\(asset.symbol)) of type \(asset.type)")
            
            // Get interest rate history for savings accounts
            let interestRates = asset.type == .savings ? asset.interestRateHistory : []
            
            // Start background enrichment and register for updates
            _ = AssetServiceManager.shared.getAssetViewModel(
                asset: asset,
                transactions: assetTransactions,
                forceRefresh: true, // Always force refresh API data to ensure we have current prices
                interestRateHistory: interestRates,
                supabaseManager: supabaseManager,
                onUpdate: { enrichedAsset in
                    // This callback runs on the main thread when the enriched data is available
                    // Get fresh transactions - important to use the latest transaction data
                    let freshAssetTransactions = self.transactions.filter { $0.asset_id == asset.id }
                    
                    // Convert the transactions to view models for display
                    let transactionViewModels = freshAssetTransactions.map { 
                        self.convertToTransactionViewModel(transaction: $0) 
                    }
                    
                    // Always recalculate values with fresh transaction data
                    // Calculate basic metrics with fresh transaction data
                    let service = BaseAssetService()
                    let totalQuantity = service.calculateTotalQuantity(transactions: freshAssetTransactions)
                    let totalCost = service.calculateTotalCost(transactions: freshAssetTransactions)
                    
                    // Create a new view model with updated values rather than modifying the existing one
                    let updatedAsset = AssetViewModel(
                        id: enrichedAsset.id,
                        symbol: enrichedAsset.symbol,
                        name: enrichedAsset.name,
                        type: enrichedAsset.type,
                        quantity: totalQuantity,
                        avgPurchasePrice: totalQuantity > 0 ? totalCost / totalQuantity : 0,
                        currentPrice: enrichedAsset.currentPrice,
                        totalValue: totalQuantity * enrichedAsset.currentPrice,
                        percentChange: calculatePerformance(totalQuantity: totalQuantity, totalCost: totalCost, currentPrice: enrichedAsset.currentPrice, transactions: freshAssetTransactions),
                        transactions: freshAssetTransactions
                    )
                    
                    // Update UI with enriched data
                    withAnimation(.smooth) {
                        // Always update the asset in the portfolio items, even if it has no transactions
                        // Find existing item by ID
                        if let index = self.portfolioItems.firstIndex(where: { $0.id == asset.id }) {
                            // Update existing item
                            self.portfolioItems[index] = updatedAsset
                        } else {
                            // Add new item if not found
                            self.portfolioItems.append(updatedAsset)
                        }
                        
                        // Sort portfolio items: assets with transactions first, then by value
                        self.portfolioItems.sort { a, b in
                            // First sort by whether they have transactions
                            if !a.transactions.isEmpty && b.transactions.isEmpty {
                                return true
                            } else if a.transactions.isEmpty && !b.transactions.isEmpty {
                                return false
                            }
                            
                            // Then by quantity (active assets go first)
                            if a.quantity > 0 && b.quantity == 0 {
                                return true
                            } else if a.quantity == 0 && b.quantity > 0 {
                                return false 
                            }
                            
                            // If both have zero quantity but transactions, sort by performance
                            if a.quantity == 0 && b.quantity == 0 && !a.transactions.isEmpty && !b.transactions.isEmpty {
                                return a.percentChange > b.percentChange
                            }
                            
                            // Otherwise sort by value (highest first)
                            return a.totalValue > b.totalValue
                        }
                        
                        // Recalculate total portfolio value (only include assets with quantity > 0)
                        self.portfolioValue = self.portfolioItems
                            .filter { $0.quantity > 0 }
                            .reduce(0) { $0 + $1.totalValue }
                    }
                }
            )
        }
        
        // Update the UI state
        await MainActor.run {
            withAnimation(.smooth) {
                isLoading = false
                isRefreshing = false
            }
        }
    }
}

#Preview {
    PortfolioView()
        .environmentObject(SupabaseManager.shared)
        .modelContainer(for: [Asset.self, Transaction.self, InterestRateHistory.self])
} 