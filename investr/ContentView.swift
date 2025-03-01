//
//  ContentView.swift
//  investr
//
//  Created by Valentin Genest on 28/02/2025.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var supabaseManager: SupabaseManager
    
    @Query private var assets: [Asset]
    @Query private var transactions: [Transaction]
    
    @State private var isLoading = false
    @State private var isRefreshing = false  // New state to differentiate between initial load and pull-to-refresh
    @State private var portfolioValue: Double = 0
    @State private var portfolioItems: [AssetViewModel] = []
    @State private var selectedTab = 0
    @State private var showingAddAsset = false
    @State private var showingAddTransaction = false
    @State private var isLoadingInProgress = false
    @State private var refreshTask: Task<Void, Never>?
    @State private var lastAPIRefreshTime: Date? = nil
    @AppStorage("apiCacheExpirationMinutes") private var apiCacheExpirationMinutes: Int = 15
    
    // API usage status
    @State private var showAPIUsageInfo = false
    @State private var monthlyAPIUsage: Int = 0
    @State private var monthlyAPILimit: Int = 500
    
    private var shouldRefreshFromAPI: Bool {
        guard let lastRefresh = lastAPIRefreshTime else { return true }
        let minimumRefreshInterval = TimeInterval(apiCacheExpirationMinutes * 60)
        return Date().timeIntervalSince(lastRefresh) >= minimumRefreshInterval
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                portfolioAssetsView
                    .navigationTitle("Portfolio")
                    .navigationBarTitleDisplayMode(.large)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button(action: {
                                showingAddAsset = true
                            }) {
                                Image(systemName: "plus")
                                    .foregroundColor(Theme.Colors.primaryText)
                            }
                        }
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button(action: { showAPIUsageInfo.toggle() }) {
                                Image(systemName: "chart.bar")
                                    .foregroundColor(getAPIUsageColor())
                            }
                        }
                    }
                    .sheet(isPresented: $showingAddAsset) {
                        AddAssetView(supabaseManager: supabaseManager) {
                            Task {
                                await loadData()
                            }
                        }
                    }
                    .refreshable {
                        await loadData()
                    }
            }
            .tabItem {
                Label("Portfolio", systemImage: "chart.pie.fill")
            }
            .tag(0)
            
            NavigationStack {
                transactionsView
                    .navigationTitle("Transactions")
                    .navigationBarTitleDisplayMode(.large)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button(action: {
                                showingAddTransaction = true
                            }) {
                                Image(systemName: "plus")
                                    .foregroundColor(Theme.Colors.primaryText)
                            }
                        }
                    }
                    .sheet(isPresented: $showingAddTransaction) {
                        AddTransactionView(supabaseManager: supabaseManager, assets: portfolioItems) {
                            Task {
                                await loadData()
                            }
                        }
                    }
                    .refreshable {
                        await loadData()
                    }
            }
            .tabItem {
                Label("Transactions", systemImage: "arrow.left.arrow.right")
            }
            .tag(1)
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(2)
        }
        .accentColor(Theme.Colors.accent)
        .preferredColorScheme(.dark)
        .task {
            // Initial data load when the view appears
            await loadData()
        }
        .onChange(of: supabaseManager.hasError) { _, hasError in
            if hasError {
                print("Displaying error: \(supabaseManager.errorMessage)")
                // You could show an alert here if needed
            }
        }
        .alert("API Usage Information", isPresented: $showAPIUsageInfo) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Monthly API usage: \(monthlyAPIUsage)/\(monthlyAPILimit) requests\nNext cache refresh in: \(timeUntilNextRefresh)")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.secondaryText)
        }
    }
    
    private var portfolioAssetsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Layout.spacing) {
                // Portfolio Summary Card
                VStack(alignment: .leading, spacing: Theme.Layout.spacing) {
                    Text("Total Portfolio Value")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.secondaryText)
                    
                    HStack {
                        Text("€\(portfolioValue, specifier: "%.2f")")
                            .font(Theme.Typography.largePrice)
                            .foregroundColor(Theme.Colors.primaryText)
                        
                        if isLoading || isRefreshing {
                            ProgressView()
                                .padding(.leading, 8)
                                .scaleEffect(0.8)
                                .tint(Theme.Colors.accent)
                        }
                    }
                }
                .cardStyle()
                
                // Assets List
                HStack {
                    Text("Assets")
                        .font(Theme.Typography.title2)
                        .fontWeight(.bold)
                        .foregroundColor(Theme.Colors.primaryText)
                    
                    if isLoading && !isRefreshing {
                        ProgressView()
                            .padding(.leading, 4)
                            .scaleEffect(0.7)
                            .tint(Theme.Colors.accent)
                    }
                    
                    Spacer()
                }
                .padding(.top)
                
                if portfolioItems.isEmpty {
                    Text("No assets found. Add your first asset to get started.")
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.secondaryText)
                        .padding()
                } else {
                    // Show active assets:
                    // - Savings accounts that have transactions
                    // - Other assets with quantity > 0
                    ForEach(portfolioItems.filter { 
                        ($0.type == .savings && $0.hasTransactions) || 
                        ($0.type != .savings && $0.totalQuantity > 0) 
                    }) { item in
                        NavigationLink(destination: AssetDetailView(asset: item)) {
                            assetRow(item: item)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    // Archived Assets section - assets with 0 quantity that aren't savings accounts
                    let archivedAssets = portfolioItems.filter { 
                        $0.type != .savings && $0.totalQuantity == 0 
                    }
                    if !archivedAssets.isEmpty {
                        Text("Archived Assets")
                            .font(Theme.Typography.title2)
                            .fontWeight(.bold)
                            .foregroundColor(Theme.Colors.primaryText)
                            .padding(.top, 30)
                        
                        ForEach(archivedAssets) { item in
                            NavigationLink(destination: AssetDetailView(asset: item)) {
                                assetRow(item: item)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
            }
            .padding()
        }
        .background(Theme.Colors.background)
    }
    
    private func assetRow(item: AssetViewModel) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                // Asset info
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(Theme.Colors.primaryText)
                    
                    HStack {
                        Text(item.symbol)
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.secondaryText)
                        
                        Text(item.type.rawValue.capitalized)
                            .font(Theme.Typography.caption)
                            .tagStyle()
                            .foregroundColor(Theme.Colors.accent)
                    }
                }
                
                Spacer()
                
                // Asset value
                VStack(alignment: .trailing, spacing: 4) {
                    Text("€\(item.totalValue, specifier: "%.2f")")
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(Theme.Colors.primaryText)
                    
                    if item.profitLoss != 0 {
                        HStack(spacing: 2) {
                            Image(systemName: item.profitLoss >= 0 ? "arrow.up" : "arrow.down")
                            Text("€\(abs(item.profitLoss), specifier: "%.2f")")
                            Text("(\(item.profitLossPercentage, specifier: "%.1f")%)")
                        }
                        .font(Theme.Typography.caption)
                        .foregroundColor(item.profitLoss >= 0 ? Theme.Colors.positive : Theme.Colors.negative)
                    }
                }
            }
            .padding(Theme.Layout.padding)
            .background(Theme.Colors.secondaryBackground)
            .cornerRadius(Theme.Layout.cornerRadius)
        }
        .padding(.vertical, 4)
    }
    
    private var transactionsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Layout.spacing) {
                if transactions.isEmpty {
                    Text("No transactions found")
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.secondaryText)
                        .padding()
                } else {
                    ForEach(transactions.sorted(by: { $0.transaction_date > $1.transaction_date })) { transaction in
                        transactionRow(transaction: transaction)
                    }
                }
            }
            .padding()
        }
        .background(Theme.Colors.background)
    }
    
    private func transactionRow(transaction: Transaction) -> some View {
        VStack(spacing: 0) {
            HStack {
                // Transaction type indicator
                Image(systemName: transaction.type == .buy ? "arrow.down" : "arrow.up")
                    .foregroundColor(transaction.type == .buy ? Theme.Colors.positive : Theme.Colors.negative)
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(transaction.type == .buy ? Theme.Colors.positive.opacity(0.2) : Theme.Colors.negative.opacity(0.2))
                    )
                
                // Asset and transaction details
                VStack(alignment: .leading, spacing: 4) {
                    Text(transaction.asset?.name ?? "Unknown Asset")
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(Theme.Colors.primaryText)
                    
                    Text(transaction.transaction_date.formatted(date: .abbreviated, time: .shortened))
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.secondaryText)
                }
                
                Spacer()
                
                // Transaction amount
                VStack(alignment: .trailing, spacing: 4) {
                    Text(transaction.type == .buy ? "+\(transaction.quantity, specifier: "%.4f")" : "-\(transaction.quantity, specifier: "%.4f")")
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(Theme.Colors.primaryText)
                    
                    Text("€\(transaction.price_per_unit, specifier: "%.2f") per unit")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.secondaryText)
                }
            }
            .padding(Theme.Layout.padding)
            .background(Theme.Colors.secondaryBackground)
            .cornerRadius(Theme.Layout.cornerRadius)
        }
        .padding(.vertical, 4)
    }
    
    private func loadData() async {
        // Cancel any existing refresh task
        refreshTask?.cancel()
        
        // Create a new task for this refresh operation
        refreshTask = Task {
            // Prevent concurrent requests
            guard !isLoadingInProgress else { 
                print("Data loading already in progress, skipping this request")
                return 
            }
            
            print("Starting data loading process")
            
            // Determine if this is a refresh or initial load
            // Initial load happens when portfolioItems is empty
            let isInitialLoad = portfolioItems.isEmpty
            isLoading = isInitialLoad
            isRefreshing = !isInitialLoad
            isLoadingInProgress = true
            
            do {
                // Use try-catch for the initial setup, but we'll handle asset-specific errors separately
                try await Task.sleep(nanoseconds: 200_000_000) // 0.2 second delay to prevent conflicts
                
                if Task.isCancelled { 
                    print("Task cancelled after delay")
                    return 
                }
                
                // Check if we have existing data and if refresh is needed
                let useCache = !isInitialLoad && !shouldRefreshFromAPI && !portfolioItems.isEmpty
                
                if useCache {
                    print("Using cached data - last refresh was at \(lastAPIRefreshTime?.formatted() ?? "unknown")")
                    // Just update the UI with the existing data
                    // This allows pull-to-refresh to work without consuming API quota
                    await MainActor.run {
                        // Trigger a UI refresh by sorting the existing items
                        portfolioItems = portfolioItems.sorted(by: { $0.totalValue > $1.totalValue })
                    }
                } else {
                    // Full refresh from API is needed
                    print("Fetching fresh data from API...")
                    
                    // Load assets and transactions in parallel
                    async let assetsTask = supabaseManager.fetchAssets()
                    async let transactionsTask = supabaseManager.fetchTransactions()
                    async let ratesTask = supabaseManager.fetchInterestRateHistory()
                    
                    do {
                        // Wait for all core data to be available
                        let (assetsResponse, transactionsResponse, interestRateHistoryResponse) = try await (assetsTask, transactionsTask, ratesTask)
                        
                        if Task.isCancelled { return }
                        
                        // Update the last refresh time
                        lastAPIRefreshTime = Date()
                        
                        // Create temporary copies of the data to work with
                        // This allows us to preserve the UI until all new data is processed
                        let oldPortfolioValue = portfolioValue
                        let oldPortfolioItems = portfolioItems
                        
                        // Create a new temporary model context for the fresh data
                        var newAssets: [Asset] = []
                        var newTransactions: [Transaction] = []
                        
                        // Clear existing data now that we have fresh data
                        print("Clearing existing data...")
                        for asset in assets {
                            modelContext.delete(asset)
                        }
                        for transaction in transactions {
                            modelContext.delete(transaction)
                        }
                        
                        // Store the basic data into the model context
                        for assetResponse in assetsResponse {
                            let asset = assetResponse.toAsset()
                            modelContext.insert(asset)
                            newAssets.append(asset)
                        }
                        
                        for transactionResponse in transactionsResponse {
                            let transaction = transactionResponse.toTransaction()
                            modelContext.insert(transaction)
                            newTransactions.append(transaction)
                        }
                        
                        for rateResponse in interestRateHistoryResponse {
                            let rate = rateResponse.toInterestRateHistory()
                            modelContext.insert(rate)
                        }
                        
                        // Load each asset independently to calculate portfolio data
                        // The loadAssetsIndependently method will progressively update the UI
                        // with the new values as they become available
                        await loadAssetsIndependently(oldItems: oldPortfolioItems)
                        
                    } catch let error as CancellationError {
                        print("Initial data fetch was cancelled: \(error.localizedDescription)")
                    } catch {
                        // Even if the main data load fails, we'll still try to use whatever assets we have in the database
                        print("Error during initial data load: \(error.localizedDescription)")
                        supabaseManager.setError(error)
                        
                        // Try to update with whatever data we have, preserving existing items
                        await loadAssetsIndependently(oldItems: portfolioItems)
                    }
                }
            } catch let error as CancellationError {
                print("Task was cancelled during initial setup: \(error.localizedDescription)")
            } catch {
                print("Error in refresh task setup: \(error.localizedDescription)")
                supabaseManager.setError(error)
            }
            
            // Always reset loading state
            isLoading = false
            isRefreshing = false
            isLoadingInProgress = false
            print("Data loading process ended, loading state reset")
        }
        
        // Wait for the task to complete
        await refreshTask?.value
        
        // Update API usage information
        let rateLimiter = Mirror(reflecting: APIRateLimiter.shared)
        for child in rateLimiter.children {
            if child.label == "monthlyRequestCount" {
                monthlyAPIUsage = child.value as? Int ?? 0
            }
            if child.label == "monthlyRequestLimit" {
                monthlyAPILimit = child.value as? Int ?? 500
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
    
    // Update the loadAssetsIndependently method to include transactions in the view model
    private func loadAssetsIndependently(oldItems: [AssetViewModel] = []) async {
        // Create new list for portfolio items
        var items: [AssetViewModel] = []
        var totalPortfolioValue: Double = 0
        
        // Process each asset independently
        for asset in assets {
            // Skip if the task was cancelled
            if Task.isCancelled { break }
            
            // Get transactions for this specific asset
            let assetTransactions = transactions.filter { $0.asset_id == asset.id }
            
            // Convert the transactions to view models for display
            let transactionViewModels = assetTransactions.map { convertToTransactionViewModel(transaction: $0) }
            
            do {
                // Process each asset type independently
                var enrichedAsset: AssetViewModel? = nil
                
                switch asset.type {
                case .etf:
                    let service = ETFService()
                    enrichedAsset = await service.enrichAssetWithPriceAndTransactions(
                        asset: asset, 
                        transactions: assetTransactions
                    )
                    
                case .crypto:
                    let service = CryptoService()
                    enrichedAsset = await service.enrichAssetWithPriceAndTransactions(
                        asset: asset, 
                        transactions: assetTransactions
                    )
                    
                case .savings:
                    let service = SavingsService()
                    let interestRates = assets.first(where: { $0.id == asset.id })?.interestRateHistory ?? []
                    enrichedAsset = await service.enrichAssetWithPriceAndTransactions(
                        asset: asset, 
                        transactions: assetTransactions,
                        interestRateHistory: interestRates,
                        supabaseManager: supabaseManager
                    )
                }
                
                // If we got data for this asset, add it to our results and include transactions
                if var asset = enrichedAsset {
                    // Add the transaction view models to the asset
                    asset.transactions = transactionViewModels
                    asset.hasTransactions = !transactionViewModels.isEmpty
                    
                    items.append(asset)
                    totalPortfolioValue += asset.totalValue
                    
                    // Update the UI with progressive results
                    await MainActor.run {
                        // Find existing item by ID
                        if let index = portfolioItems.firstIndex(where: { $0.id == asset.id }) {
                            // Replace it with the new enriched asset
                            portfolioItems[index] = asset
                        } else {
                            // If it's a new asset, append it
                            portfolioItems.append(asset)
                        }
                        
                        // Sort the list by value
                        portfolioItems = portfolioItems.sorted(by: { $0.totalValue > $1.totalValue })
                        
                        // Update the total portfolio value progressively
                        // We calculate from the current items to ensure accuracy
                        portfolioValue = portfolioItems.reduce(0) { $0 + $1.totalValue }
                    }
                }
            } catch {
                // Log the error but continue processing other assets
                print("Error loading asset \(asset.name): \(error.localizedDescription)")
            }
        }
        
        // Final UI update with all results
        await MainActor.run {
            // We now only remove items that no longer exist in the dataset
            let loadedAssetIds = items.map { $0.id }
            
            // Keep any old items that don't have updated values, if desired
            // This is where you'd implement logic to preserve items that failed to update
            
            // Remove items from portfolioItems that no longer exist in the data
            portfolioItems = portfolioItems.filter { loadedAssetIds.contains($0.id) }
            
            // Ensure items are sorted by value
            portfolioItems = portfolioItems.sorted(by: { $0.totalValue > $1.totalValue })
            
            // Only recalculate the final portfolio value if we have new items
            if !items.isEmpty {
                portfolioValue = portfolioItems.reduce(0) { $0 + $1.totalValue }
            }
        }
    }
    
    // Helper methods for API usage information
    private func getAPIUsageColor() -> Color {
        let usage = Double(monthlyAPIUsage) / Double(monthlyAPILimit)
        if usage < 0.5 {
            return Theme.Colors.positive
        } else if usage < 0.8 {
            return Color.yellow
        } else {
            return Theme.Colors.negative
        }
    }
    
    private var timeUntilNextRefresh: String {
        guard let lastRefresh = lastAPIRefreshTime else { return "Now" }
        
        let nextRefreshTime = lastRefresh.addingTimeInterval(Double(apiCacheExpirationMinutes * 60))
        let timeRemaining = nextRefreshTime.timeIntervalSince(Date())
        
        if timeRemaining <= 0 {
            return "Now"
        }
        
        let minutes = Int(timeRemaining / 60)
        let seconds = Int(timeRemaining.truncatingRemainder(dividingBy: 60))
        
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }
}

// MARK: - Asset Detail View
struct AssetDetailView: View {
    let asset: AssetViewModel
    
    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()
            
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Layout.spacing) {
                    // Header - Asset Info
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(asset.name)
                                .font(Theme.Typography.title)
                                .foregroundColor(Theme.Colors.primaryText)
                            
                            HStack(spacing: 8) {
                                Text(asset.symbol)
                                    .font(Theme.Typography.bodyBold)
                                    .foregroundColor(Theme.Colors.secondaryText)
                                
                                Text(asset.type.rawValue.capitalized)
                                    .font(Theme.Typography.caption)
                                    .tagStyle()
                                    .foregroundColor(Theme.Colors.accent)
                            }
                        }
                        
                        Spacer()
                        
                        // Current Price
                        VStack(alignment: .trailing, spacing: 3) {
                            Text("€\(asset.currentPrice, specifier: "%.2f")")
                                .font(Theme.Typography.price)
                                .foregroundColor(Theme.Colors.primaryText)
                            
                            if let change24h = asset.change24h {
                                HStack(spacing: 2) {
                                    Image(systemName: change24h >= 0 ? "arrow.up" : "arrow.down")
                                    Text("\(abs(change24h), specifier: "%.2f")%")
                                }
                                .font(Theme.Typography.caption)
                                .foregroundColor(change24h >= 0 ? Theme.Colors.positive : Theme.Colors.negative)
                            }
                        }
                    }
                    .cardStyle()
                    
                    // Position Summary Card
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Your Position")
                            .font(Theme.Typography.title3)
                            .foregroundColor(Theme.Colors.primaryText)
                        
                        Divider()
                            .background(Theme.Colors.separator)
                        
                        // Main position stats in a grid
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                            // Quantity
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Quantity")
                                    .font(Theme.Typography.caption)
                                    .foregroundColor(Theme.Colors.secondaryText)
                                Text("\(asset.totalQuantity, specifier: "%.4f")")
                                    .font(Theme.Typography.bodyBold)
                                    .foregroundColor(Theme.Colors.primaryText)
                            }
                            
                            // Total Value
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("Total Value")
                                    .font(Theme.Typography.caption)
                                    .foregroundColor(Theme.Colors.secondaryText)
                                Text("€\(asset.totalValue, specifier: "%.2f")")
                                    .font(Theme.Typography.bodyBold)
                                    .foregroundColor(Theme.Colors.primaryText)
                            }
                            
                            // Average Price
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Average Price")
                                    .font(Theme.Typography.caption)
                                    .foregroundColor(Theme.Colors.secondaryText)
                                Text("€\(asset.averagePrice, specifier: "%.2f")")
                                    .font(Theme.Typography.bodyBold)
                                    .foregroundColor(Theme.Colors.primaryText)
                            }
                            
                            // Profit/Loss
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("Profit/Loss")
                                    .font(Theme.Typography.caption)
                                    .foregroundColor(Theme.Colors.secondaryText)
                                HStack(spacing: 4) {
                                    Text("€\(asset.profitLoss, specifier: "%.2f")")
                                        .font(Theme.Typography.bodyBold)
                                        .foregroundColor(asset.profitLoss >= 0 ? Theme.Colors.positive : Theme.Colors.negative)
                                }
                                Text("(\(asset.profitLossPercentage, specifier: "%.2f")%)")
                                    .font(Theme.Typography.caption)
                                    .foregroundColor(asset.profitLoss >= 0 ? Theme.Colors.positive : Theme.Colors.negative)
                            }
                        }
                    }
                    .cardStyle()
                    
                    // Transactions History
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Transaction History")
                            .font(Theme.Typography.title3)
                            .foregroundColor(Theme.Colors.primaryText)
                        
                        if asset.transactions.isEmpty {
                            Text("No transactions found for this asset")
                                .font(Theme.Typography.body)
                                .foregroundColor(Theme.Colors.secondaryText)
                                .padding()
                        } else {
                            ForEach(asset.transactions.sorted(by: { $0.date > $1.date })) { transaction in
                                HStack {
                                    // Transaction type indicator
                                    Image(systemName: transaction.type == .buy ? "arrow.down" : "arrow.up")
                                        .foregroundColor(transaction.type == .buy ? Theme.Colors.positive : Theme.Colors.negative)
                                        .font(.system(size: 14, weight: .bold))
                                        .frame(width: 28, height: 28)
                                        .background(
                                            Circle()
                                                .fill(transaction.type == .buy ? Theme.Colors.positive.opacity(0.2) : Theme.Colors.negative.opacity(0.2))
                                        )
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(transaction.type == .buy ? "Buy" : "Sell")
                                            .font(Theme.Typography.bodyBold)
                                            .foregroundColor(Theme.Colors.primaryText)
                                        
                                        Text(transaction.date.formatted(date: .abbreviated, time: .shortened))
                                            .font(Theme.Typography.caption)
                                            .foregroundColor(Theme.Colors.secondaryText)
                                    }
                                    
                                    Spacer()
                                    
                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text(transaction.type == .buy ? "+\(transaction.quantity, specifier: "%.4f")" : "-\(transaction.quantity, specifier: "%.4f")")
                                            .font(Theme.Typography.bodyBold)
                                            .foregroundColor(Theme.Colors.primaryText)
                                        
                                        Text("€\(transaction.price, specifier: "%.2f") per unit")
                                            .font(Theme.Typography.caption)
                                            .foregroundColor(Theme.Colors.secondaryText)
                                    }
                                }
                                .padding(Theme.Layout.padding)
                                .background(Theme.Colors.secondaryBackground)
                                .cornerRadius(Theme.Layout.cornerRadius)
                            }
                        }
                    }
                }
                .padding(Theme.Layout.padding)
            }
        }
        .navigationTitle("Asset Details")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Add Asset View
struct AddAssetView: View {
    @Environment(\.dismiss) private var dismiss
    var supabaseManager: SupabaseManager
    var onComplete: () -> Void
    
    @State private var searchQuery = ""
    @State private var symbol = ""
    @State private var name = ""
    @State private var isin = ""
    @State private var selectedType: AssetType = .etf
    @State private var isAddingAsset = false
    @State private var errorMessage: String?
    
    var types: [AssetType] = [.etf, .crypto, .savings]
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.background.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: Theme.Layout.spacing) {
                        // Search section
                        VStack(alignment: .leading, spacing: Theme.Layout.smallSpacing) {
                            Text("Search Asset")
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.secondaryText)
                                .padding(.horizontal, Theme.Layout.padding)
                            
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(Theme.Colors.secondaryText)
                                TextField("Search for an asset...", text: $searchQuery)
                                    .foregroundColor(Theme.Colors.primaryText)
                            }
                            .padding()
                            .background(Theme.Colors.secondaryBackground)
                            .cornerRadius(Theme.Layout.cornerRadius)
                            .padding(.horizontal, Theme.Layout.padding)
                        }
                        
                        // Form fields
                        VStack(alignment: .leading, spacing: Theme.Layout.spacing) {
                            Text("Asset Details")
                                .font(Theme.Typography.title3)
                                .foregroundColor(Theme.Colors.primaryText)
                                .padding(.horizontal, Theme.Layout.padding)
                                .padding(.top, 8)
                            
                            VStack(spacing: Theme.Layout.spacing) {
                                // Symbol field
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Symbol *")
                                        .font(Theme.Typography.caption)
                                        .foregroundColor(Theme.Colors.secondaryText)
                                    
                                    TextField("", text: $symbol)
                                        .padding()
                                        .background(Theme.Colors.secondaryBackground)
                                        .cornerRadius(Theme.Layout.cornerRadius)
                                        .foregroundColor(Theme.Colors.primaryText)
                                        .autocapitalization(.none)
                                }
                                
                                // Name field
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Name *")
                                        .font(Theme.Typography.caption)
                                        .foregroundColor(Theme.Colors.secondaryText)
                                    
                                    TextField("", text: $name)
                                        .padding()
                                        .background(Theme.Colors.secondaryBackground)
                                        .cornerRadius(Theme.Layout.cornerRadius)
                                        .foregroundColor(Theme.Colors.primaryText)
                                }
                                
                                // ISIN field
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("ISIN")
                                        .font(Theme.Typography.caption)
                                        .foregroundColor(Theme.Colors.secondaryText)
                                    
                                    TextField("", text: $isin)
                                        .padding()
                                        .background(Theme.Colors.secondaryBackground)
                                        .cornerRadius(Theme.Layout.cornerRadius)
                                        .foregroundColor(Theme.Colors.primaryText)
                                        .autocapitalization(.none)
                                }
                                
                                // Type picker
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Type *")
                                        .font(Theme.Typography.caption)
                                        .foregroundColor(Theme.Colors.secondaryText)
                                    
                                    Picker("", selection: $selectedType) {
                                        ForEach(types, id: \.self) { type in
                                            Text(type.rawValue.capitalized)
                                        }
                                    }
                                    .pickerStyle(SegmentedPickerStyle())
                                    .padding(.vertical, 4)
                                }
                            }
                            .padding(.horizontal, Theme.Layout.padding)
                        }
                        
                        // Error message
                        if let errorMessage = errorMessage {
                            Text(errorMessage)
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.negative)
                                .padding(.horizontal, Theme.Layout.padding)
                                .padding(.top, Theme.Layout.smallSpacing)
                        }
                        
                        // Add button
                        Button(action: addAsset) {
                            HStack {
                                if isAddingAsset {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle())
                                        .tint(Theme.Colors.primaryText)
                                } else {
                                    Text("Add Asset")
                                        .font(Theme.Typography.bodyBold)
                                        .foregroundColor(Theme.Colors.primaryText)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                (isAddingAsset || symbol.isEmpty || name.isEmpty) ? 
                                    Theme.Colors.secondaryBackground : Theme.Colors.accent
                            )
                            .cornerRadius(Theme.Layout.cornerRadius)
                        }
                        .disabled(isAddingAsset || symbol.isEmpty || name.isEmpty)
                        .padding(.horizontal, Theme.Layout.padding)
                        .padding(.top, 24)
                    }
                    .padding(.vertical, Theme.Layout.padding)
                }
            }
            .navigationTitle("Add Asset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(Theme.Colors.accent)
                }
            }
        }
    }
    
    private func addAsset() {
        guard !symbol.isEmpty, !name.isEmpty else {
            errorMessage = "Symbol and name are required."
            return
        }
        
        isAddingAsset = true
        errorMessage = nil
        
        Task {
            do {
                // Create a new asset in Supabase using the SupabaseManager
                let assetId = try await supabaseManager.addAsset(
                    symbol: symbol,
                    name: name,
                    isin: isin.isEmpty ? nil : isin,
                    type: selectedType
                )
                
                if assetId != nil {
                    // Asset was added successfully
                    onComplete()
                    dismiss()
                } else {
                    // Failed to add asset
                    errorMessage = "Failed to add asset. Please try again."
                    isAddingAsset = false
                }
            } catch {
                // Handle any errors
                errorMessage = "Error: \(error.localizedDescription)"
                isAddingAsset = false
            }
        }
    }
}

// MARK: - Add Transaction View
struct AddTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    var supabaseManager: SupabaseManager
    var assets: [AssetViewModel]
    var onComplete: () -> Void
    
    @State private var selectedAsset: AssetViewModel?
    @State private var transactionType: TransactionType = .buy
    @State private var quantity: String = ""
    @State private var pricePerUnit: String = ""
    @State private var totalAmount: String = ""
    @State private var transactionDate = Date()
    @State private var isAddingTransaction = false
    @State private var errorMessage: String?
    
    private var calculatedTotalAmount: Double {
        guard let quantityValue = Double(quantity), let priceValue = Double(pricePerUnit) else {
            return 0
        }
        return quantityValue * priceValue
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.background.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: Theme.Layout.spacing) {
                        // Asset Selection
                        VStack(alignment: .leading, spacing: Theme.Layout.smallSpacing) {
                            Text("Asset")
                                .font(Theme.Typography.title3)
                                .foregroundColor(Theme.Colors.primaryText)
                                .padding(.horizontal, Theme.Layout.padding)
                            
                            Menu {
                                ForEach(assets) { asset in
                                    Button(action: {
                                        selectedAsset = asset
                                    }) {
                                        Text(asset.name)
                                    }
                                }
                            } label: {
                                HStack {
                                    Text(selectedAsset?.name ?? "Select an asset")
                                        .foregroundColor(selectedAsset != nil ? Theme.Colors.primaryText : Theme.Colors.secondaryText)
                                        .font(Theme.Typography.body)
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.down")
                                        .foregroundColor(Theme.Colors.secondaryText)
                                        .font(.caption)
                                }
                                .padding()
                                .background(Theme.Colors.secondaryBackground)
                                .cornerRadius(Theme.Layout.cornerRadius)
                                .padding(.horizontal, Theme.Layout.padding)
                            }
                        }
                        
                        // Transaction Details
                        VStack(alignment: .leading, spacing: Theme.Layout.smallSpacing) {
                            Text("Transaction Details")
                                .font(Theme.Typography.title3)
                                .foregroundColor(Theme.Colors.primaryText)
                                .padding(.horizontal, Theme.Layout.padding)
                                .padding(.top, 8)
                            
                            VStack(spacing: Theme.Layout.spacing) {
                                // Transaction Type
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Type")
                                        .font(Theme.Typography.caption)
                                        .foregroundColor(Theme.Colors.secondaryText)
                                    
                                    Picker("", selection: $transactionType) {
                                        Text("Buy").tag(TransactionType.buy)
                                        Text("Sell").tag(TransactionType.sell)
                                    }
                                    .pickerStyle(SegmentedPickerStyle())
                                    .padding(.vertical, 4)
                                }
                                
                                // Transaction Date
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Date")
                                        .font(Theme.Typography.caption)
                                        .foregroundColor(Theme.Colors.secondaryText)
                                    
                                    DatePicker("", selection: $transactionDate, displayedComponents: .date)
                                        .datePickerStyle(.compact)
                                        .padding()
                                        .background(Theme.Colors.secondaryBackground)
                                        .cornerRadius(Theme.Layout.cornerRadius)
                                        .foregroundColor(Theme.Colors.primaryText)
                                }
                                
                                // Quantity
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Quantity")
                                        .font(Theme.Typography.caption)
                                        .foregroundColor(Theme.Colors.secondaryText)
                                    
                                    TextField("", text: $quantity)
                                        .keyboardType(.decimalPad)
                                        .padding()
                                        .background(Theme.Colors.secondaryBackground)
                                        .cornerRadius(Theme.Layout.cornerRadius)
                                        .foregroundColor(Theme.Colors.primaryText)
                                        .onChange(of: quantity) { _, newValue in
                                            if let quantityValue = Double(newValue), let priceValue = Double(pricePerUnit) {
                                                totalAmount = "\(quantityValue * priceValue)"
                                            }
                                        }
                                }
                                
                                // Price per Unit
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Price per Unit")
                                        .font(Theme.Typography.caption)
                                        .foregroundColor(Theme.Colors.secondaryText)
                                    
                                    TextField("", text: $pricePerUnit)
                                        .keyboardType(.decimalPad)
                                        .padding()
                                        .background(Theme.Colors.secondaryBackground)
                                        .cornerRadius(Theme.Layout.cornerRadius)
                                        .foregroundColor(Theme.Colors.primaryText)
                                        .onChange(of: pricePerUnit) { _, newValue in
                                            if let quantityValue = Double(quantity), let priceValue = Double(newValue) {
                                                totalAmount = "\(quantityValue * priceValue)"
                                            }
                                        }
                                }
                                
                                // Total Amount
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Total Amount")
                                        .font(Theme.Typography.caption)
                                        .foregroundColor(Theme.Colors.secondaryText)
                                    
                                    HStack {
                                        Spacer()
                                        Text("€\(calculatedTotalAmount, specifier: "%.2f")")
                                            .font(Theme.Typography.price)
                                            .foregroundColor(Theme.Colors.primaryText)
                                    }
                                    .padding()
                                    .background(Theme.Colors.secondaryBackground)
                                    .cornerRadius(Theme.Layout.cornerRadius)
                                }
                            }
                            .padding(.horizontal, Theme.Layout.padding)
                        }
                        
                        // Error message
                        if let errorMessage = errorMessage {
                            Text(errorMessage)
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.negative)
                                .padding(.horizontal, Theme.Layout.padding)
                                .padding(.top, Theme.Layout.smallSpacing)
                        }
                        
                        // Add Button
                        Button(action: addTransaction) {
                            HStack {
                                if isAddingTransaction {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle())
                                        .tint(Theme.Colors.primaryText)
                                } else {
                                    Text("Add Transaction")
                                        .font(Theme.Typography.bodyBold)
                                        .foregroundColor(Theme.Colors.primaryText)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                (isAddingTransaction || selectedAsset == nil || quantity.isEmpty || pricePerUnit.isEmpty) ? 
                                    Theme.Colors.secondaryBackground : Theme.Colors.accent
                            )
                            .cornerRadius(Theme.Layout.cornerRadius)
                        }
                        .disabled(isAddingTransaction || selectedAsset == nil || quantity.isEmpty || pricePerUnit.isEmpty)
                        .padding(.horizontal, Theme.Layout.padding)
                        .padding(.top, 24)
                    }
                    .padding(.vertical, Theme.Layout.padding)
                }
            }
            .navigationTitle("Add Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(Theme.Colors.accent)
                }
            }
        }
    }
    
    private func addTransaction() {
        guard let selectedAsset = selectedAsset,
              let quantityValue = Double(quantity),
              let priceValue = Double(pricePerUnit) else {
            errorMessage = "Please fill in all fields correctly."
            return
        }
        
        isAddingTransaction = true
        errorMessage = nil
        
        // Calculate the total amount
        let totalAmount = quantityValue * priceValue
        
        Task {
            do {
                // Create a new transaction in Supabase using the SupabaseManager
                let transactionId = try await supabaseManager.addTransaction(
                    assetId: selectedAsset.id,
                    type: transactionType,
                    quantity: quantityValue,
                    pricePerUnit: priceValue,
                    totalAmount: totalAmount,
                    date: transactionDate
                )
                
                if !transactionId.isEmpty {
                    // Transaction was added successfully
                    onComplete()
                    dismiss()
                } else {
                    // Failed to add transaction
                    errorMessage = "Failed to add transaction. Please try again."
                    isAddingTransaction = false
                }
            } catch {
                // Handle any errors
                errorMessage = "Error: \(error.localizedDescription)"
                isAddingTransaction = false
            }
        }
    }
}

// MARK: - Asset View Model
struct AssetViewModel: Identifiable, Hashable {
    var id: String
    var name: String
    var symbol: String
    var type: AssetType
    var currentPrice: Double
    var totalValue: Double
    var totalQuantity: Double
    var averagePrice: Double
    var profitLoss: Double
    var profitLossPercentage: Double
    var transactions: [TransactionViewModel] = []
    
    // Optional fields based on asset type
    var change24h: Double?
    var dayHigh: Double?
    var dayLow: Double?
    var previousClose: Double?
    var volume: Double?
    var interest_rate: Double?
    var accruedInterest: Double?
    var hasTransactions: Bool = false
    
    // Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: AssetViewModel, rhs: AssetViewModel) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Transaction View Model
struct TransactionViewModel: Identifiable, Hashable {
    var id: String
    var assetId: String
    var assetName: String
    var type: TransactionType
    var quantity: Double
    var price: Double
    var totalAmount: Double
    var date: Date
    
    // Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: TransactionViewModel, rhs: TransactionViewModel) -> Bool {
        lhs.id == rhs.id
    }
}

// Preview
#Preview {
    ContentView()
        .modelContainer(for: [Asset.self, Transaction.self, InterestRateHistory.self], inMemory: true)
        .environmentObject(SupabaseManager.shared)
}
