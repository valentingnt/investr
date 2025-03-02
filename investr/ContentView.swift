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
    @Namespace private var namespace
    
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
                    }
                    .sheet(isPresented: $showingAddAsset) {
                        AddAssetView() {
                            Task {
                                await loadData()
                            }
                        }
                        .environmentObject(supabaseManager)
                    }
                    .refreshable {
                        await loadData()
                    }
                    .animation(.smooth, value: portfolioItems)
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
                        AddTransactionView(assets: portfolioItems) {
                            // Perform a complete refresh when a transaction is added
                            Task {
                                print("Transaction added - performing full data refresh")
                                
                                // Clear portfolio items to force a complete rebuild
                                portfolioItems = []
                                
                                // Load fresh data from the API
                                await loadData()
                            }
                        }
                        .environmentObject(supabaseManager)
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
        .task {
            // Initial data load when the view appears
            await loadData()
        }
        .onChange(of: supabaseManager.hasError) { _, hasError in
            if hasError {
                print("Displaying error: \(supabaseManager.errorMessage)")
                // Only handle global errors here, not transaction-specific errors
                // which should be handled in their respective views
                
                // Optionally, you could show a toast or alert here for system-wide errors
                // but avoid showing errors that might be handled by child views
            }
        }
        // Listen for changes to transactions in the model context
        .onChange(of: transactions.count) { oldCount, newCount in
            if oldCount != newCount {
                print("Transaction count changed in ContentView: \(oldCount) to \(newCount)")
                Task {
                    // Reload assets with updated data
                    await loadAssetsIndependently()
                }
            }
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
                        Text("\(FormatHelper.formatCurrency(portfolioValue)) €")
                            .font(.system(size: 28, weight: .bold, design: .monospaced))
                            .foregroundColor(Theme.Colors.primaryText)
                            .contentTransition(.numericText())
                            .animation(.smooth, value: portfolioValue)
                        
                        if isLoading || isRefreshing {
                            ProgressView()
                                .padding(.leading, 8)
                                .scaleEffect(0.8)
                                .tint(Theme.Colors.accent)
                        }
                    }
                    
                    Divider()
                        .background(Theme.Colors.separator)
                        .padding(.vertical, 4)
                    
                    // Portfolio Details Grid
                    HStack(alignment: .top, spacing: Theme.Layout.spacing * 2) {
                        // Left Column - Gross Assets and Invested
                        VStack(alignment: .leading, spacing: 12) {
                            // Gross Assets (PATRIMOINE BRUT)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("PATRIMOINE BRUT")
                                    .font(Theme.Typography.caption)
                                    .foregroundColor(Theme.Colors.secondaryText)
                                
                                Text("\(FormatHelper.formatCurrency(portfolioValue)) €")
                                    .font(.system(.body, design: .monospaced).bold())
                                    .foregroundColor(Theme.Colors.primaryText)
                                    .contentTransition(.numericText())
                                    .animation(.smooth, value: portfolioValue)
                            }
                            
                            // Invested (INVESTI)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("INVESTI")
                                    .font(Theme.Typography.caption)
                                    .foregroundColor(Theme.Colors.secondaryText)
                                
                                let totalInvested = calculateTotalInvested()
                                Text("\(FormatHelper.formatCurrency(totalInvested)) €")
                                    .font(.system(.body, design: .monospaced).bold())
                                    .foregroundColor(Theme.Colors.primaryText)
                                    .contentTransition(.numericText())
                                    .animation(.smooth, value: totalInvested)
                            }
                        }
                        
                        Spacer()
                        
                        // Right Column - Performance and Profit/Loss
                        VStack(alignment: .trailing, spacing: 12) {
                            // Performance
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("PERFORMANCE")
                                    .font(Theme.Typography.caption)
                                    .foregroundColor(Theme.Colors.secondaryText)
                                
                                let totalInvested = calculateTotalInvested()
                                let performancePercentage = totalInvested > 0 ? ((portfolioValue - totalInvested) / totalInvested) * 100 : 0
                                
                                HStack(spacing: 2) {
                                    if performancePercentage != 0 {
                                        Image(systemName: performancePercentage >= 0 ? "arrow.up" : "arrow.down")
                                    }
                                    Text("\(FormatHelper.formatPercentage(performancePercentage))")
                                        .font(.system(.body, design: .monospaced).bold())
                                        .contentTransition(.numericText())
                                        .animation(.smooth, value: performancePercentage)
                                }
                                .foregroundColor(performancePercentage >= 0 ? Theme.Colors.positive : Theme.Colors.negative)
                            }
                            
                            // Profit/Loss (PLUS/MOINS VALUE)
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("PLUS/MOINS VALUE")
                                    .font(Theme.Typography.caption)
                                    .foregroundColor(Theme.Colors.secondaryText)
                                
                                let totalInvested = calculateTotalInvested()
                                let profitLoss = portfolioValue - totalInvested
                                
                                Text("\(FormatHelper.formatCurrency(profitLoss)) €")
                                    .font(.system(.body, design: .monospaced).bold())
                                    .foregroundColor(profitLoss >= 0 ? Theme.Colors.positive : Theme.Colors.negative)
                                    .contentTransition(.numericText())
                                    .animation(.smooth, value: profitLoss)
                            }
                        }
                    }
                }
                .padding(16)
                .background(Theme.Colors.secondaryBackground)
                .cornerRadius(Theme.Layout.cornerRadius)
                
                // Assets List
                HStack {
                    Text("Assets")
                        .font(Theme.Typography.title3)
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
                    VStack(alignment: .leading, spacing: 24) {
                        // Active Assets Section
                        VStack(alignment: .leading, spacing: 16) {
                            // Show active assets:
                            // - Savings accounts that have transactions
                            // - Other assets with quantity > 0
                            ForEach(portfolioItems.filter { 
                                ($0.type == .savings && $0.hasTransactions) || 
                                ($0.type != .savings && $0.totalQuantity > 0) 
                            }) { item in
                                NavigationLink(destination: AssetDetailView(asset: item)
                                    .environmentObject(supabaseManager)
                                    .navigationTransition(.zoom(sourceID: "asset_\(item.id)", in: namespace))
                                ) {
                                    assetRow(item: item)
                                        .matchedTransitionSource(id: "asset_\(item.id)", in: namespace)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        
                        // Archived Assets section - assets with 0 quantity that aren't savings accounts
                        let archivedAssets = portfolioItems.filter { 
                            $0.type != .savings && $0.totalQuantity == 0 
                        }
                        if !archivedAssets.isEmpty {
                            Divider()
                                .background(Theme.Colors.separator)
                                .padding(.vertical, 4)
                            
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Archived Assets")
                                    .font(Theme.Typography.title3)
                                    .foregroundColor(Theme.Colors.primaryText)
                                    .padding(.bottom, 4)
                                
                                ForEach(archivedAssets) { item in
                                    NavigationLink(destination: AssetDetailView(asset: item)
                                        .environmentObject(supabaseManager)
                                        .navigationTransition(.zoom(sourceID: "asset_\(item.id)", in: namespace))
                                    ) {
                                        assetRow(item: item)
                                            .matchedTransitionSource(id: "asset_\(item.id)", in: namespace)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                        }
                    }
                    .padding(16)
                    .background(Theme.Colors.secondaryBackground)
                    .cornerRadius(16)
                }
            }
            .padding(16)
        }
        .background(Theme.Colors.background)
    }
    
    private func assetRow(item: AssetViewModel) -> some View {
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
                Text("\(FormatHelper.formatCurrency(item.totalValue)) €")
                    .font(.system(.body, design: .monospaced).bold())
                    .foregroundColor(Theme.Colors.primaryText)
                    .contentTransition(.numericText())
                    .animation(.smooth, value: item.totalValue)
                
                if item.profitLoss != 0 {
                    HStack(spacing: 2) {
                        Image(systemName: item.profitLoss >= 0 ? "arrow.up" : "arrow.down")
                        Text("\(FormatHelper.formatCurrency(abs(item.profitLoss))) €")
                            .font(.system(.caption, design: .monospaced))
                            .contentTransition(.numericText())
                            .animation(.smooth, value: item.profitLoss)
                        Text("(\(FormatHelper.formatPercentage(item.profitLossPercentage)))")
                            .font(.system(.caption, design: .monospaced))
                            .contentTransition(.numericText())
                            .animation(.smooth, value: item.profitLossPercentage)
                    }
                    .foregroundColor(item.profitLoss >= 0 ? Theme.Colors.positive : Theme.Colors.negative)
                }
            }
        }
        .padding(.vertical, 12)
    }
    
    private var transactionsView: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()
            
            VStack(alignment: .leading, spacing: 0) {
                if transactions.isEmpty {
                    VStack {
                        Spacer()
                        Text("No transactions found")
                            .font(Theme.Typography.body)
                            .foregroundColor(Theme.Colors.secondaryText)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    List {
                        ForEach(transactions.sorted(by: { $0.transaction_date > $1.transaction_date })) { transaction in
                            transactionRow(transaction: transaction)
                                .listRowBackground(Theme.Colors.secondaryBackground)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        deleteTransaction(transaction: transaction)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .overlay {
                if isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.2))
                }
            }
        }
    }
    
    private func transactionRow(transaction: Transaction) -> some View {
        VStack(spacing: 0) {
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
                    
                    Text(transaction.transaction_date.formatted(date: .abbreviated, time: .shortened))
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.secondaryText)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text(transaction.type == .buy ? "+\(FormatHelper.formatQuantity(transaction.quantity))" : "-\(FormatHelper.formatQuantity(transaction.quantity))")
                        .font(.system(.body, design: .monospaced).bold())
                        .foregroundColor(Theme.Colors.primaryText)
                        .contentTransition(.numericText())
                        .animation(.smooth, value: transaction.quantity)
                    
                    Text("\(FormatHelper.formatCurrency(transaction.price_per_unit)) € per unit")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(Theme.Colors.secondaryText)
                        .contentTransition(.numericText())
                        .animation(.smooth, value: transaction.price_per_unit)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
        }
        .background(Theme.Colors.secondaryBackground)
        .cornerRadius(Theme.Layout.cornerRadius)
        .padding(.vertical, 4)
    }
    
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
    
    // Update the loadAssetsIndependently method to handle refreshes better
    private func loadAssetsIndependently(oldItems: [AssetViewModel] = []) async {
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
                    
                    // Update the base view model with local calculations
                    baseViewModel.totalQuantity = totalQuantity
                    baseViewModel.averagePrice = totalQuantity > 0 ? totalCost / totalQuantity : 0
                    baseViewModel.transactions = transactionViewModels
                    baseViewModel.hasTransactions = !transactionViewModels.isEmpty
                    
                    // Add to portfolio items immediately
                    portfolioItems.append(baseViewModel)
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
                    
                    // Create a mutable copy with transactions
                    var mutableAsset = enrichedAsset
                    mutableAsset.transactions = transactionViewModels
                    mutableAsset.hasTransactions = !transactionViewModels.isEmpty
                    
                    // Always recalculate values with fresh transaction data
                    // Calculate basic metrics with fresh transaction data
                    let service = BaseAssetService()
                    let totalQuantity = service.calculateTotalQuantity(transactions: freshAssetTransactions)
                    let totalCost = service.calculateTotalCost(transactions: freshAssetTransactions)
                    
                    // Keep price from API but update quantity and calculations
                    let price = mutableAsset.currentPrice
                    mutableAsset.totalQuantity = totalQuantity
                    mutableAsset.totalValue = totalQuantity * price
                    mutableAsset.averagePrice = totalQuantity > 0 ? totalCost / totalQuantity : 0
                    mutableAsset.profitLoss = (totalQuantity * price) - totalCost
                    mutableAsset.profitLossPercentage = totalCost > 0 ? ((totalQuantity * price - totalCost) / totalCost) * 100 : 0
                    
                    // Update UI with enriched data
                    withAnimation(.smooth) {
                        // Find existing item by ID
                        if let index = self.portfolioItems.firstIndex(where: { $0.id == asset.id }) {
                            // Update existing item
                            self.portfolioItems[index] = mutableAsset
                        } else {
                            // Add new item if not found
                            self.portfolioItems.append(mutableAsset)
                        }
                        
                        // Keep portfolio items sorted by value
                        self.portfolioItems.sort { $0.totalValue > $1.totalValue }
                        
                        // Recalculate total portfolio value
                        self.portfolioValue = self.portfolioItems.reduce(0) { $0 + $1.totalValue }
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
    
    // Helper function to execute a task with a timeout
    private func withTimeout<T>(seconds: Double, operation: @escaping () async throws -> T?) async throws -> T? {
        print("Starting operation with \(seconds) second timeout")
        return try await withTaskGroup(of: Optional<T>.self) { group in
            // Create a unique ID for this particular task group for better tracking
            let taskId = UUID().uuidString.prefix(8)
            
            // Add the main operation
            group.addTask {
                do {
                    print("[\(taskId)] Starting main operation")
                    let result = try await operation()
                    print("[\(taskId)] Main operation completed successfully")
                    return result
                } catch let error as CancellationError {
                    print("[\(taskId)] Operation was cancelled: \(error.localizedDescription)")
                    return nil
                } catch {
                    print("[\(taskId)] Operation failed with error: \(error.localizedDescription)")
                    return nil
                }
            }
            
            // Add a timeout task
            group.addTask {
                do {
                    print("[\(taskId)] Starting timeout task for \(seconds) seconds")
                    try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                    print("[\(taskId)] Timeout reached after \(seconds) seconds")
                    // Return nil after timeout
                    return nil
                } catch {
                    print("[\(taskId)] Timeout task was cancelled")
                    return nil
                }
            }
            
            // Take the first completion (either the operation or the timeout)
            if let result = await group.next() {
                print("[\(taskId)] Task completed - cancelling any remaining tasks")
                // Cancel any remaining tasks
                group.cancelAll()
                return result
            }
            
            // This shouldn't happen but return nil just in case
            print("[\(taskId)] No task completed (unexpected) - returning nil")
            return nil
        }
    }
    
    private func deleteTransaction(transaction: Transaction) {
        // Show a loading indicator
        isLoading = true
        
        Task {
            do {
                // Delete from Supabase
                let success = try await supabaseManager.deleteTransaction(id: transaction.id)
                
                if success {
                    await MainActor.run {
                        // Delete from SwiftData
                        modelContext.delete(transaction)
                        
                        // Refresh portfolio data to update calculated values
                        Task {
                            await loadData()
                        }
                    }
                }
            } catch {
                print("Error deleting transaction: \(error.localizedDescription)")
                
                // Show error message
                await MainActor.run {
                    supabaseManager.setError(error)
                }
            }
            
            await MainActor.run {
                isLoading = false
            }
        }
    }
    
    private func calculateTotalInvested() -> Double {
        // Calculate the total invested amount across all assets
        let service = BaseAssetService()
        let totalInvested = portfolioItems.reduce(0.0) { sum, item in
            // For each asset, calculate its total cost from transactions
            let assetTransactions = transactions.filter { $0.asset_id == item.id }
            let assetCost = service.calculateTotalCost(transactions: assetTransactions)
            return sum + assetCost
        }
        return totalInvested
    }
}

// MARK: - Asset Detail View
struct AssetDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var supabaseManager: SupabaseManager
    @Environment(\.dismiss) private var dismiss
    
    // Instead of a simple let asset, we'll use @State so we can update it
    @State private var asset: AssetViewModel
    @State private var isRefreshing = false
    @State private var showDeleteAlert = false
    
    // Get fresh transactions from SwiftData
    @Query private var transactions: [Transaction]
    
    // We need an asset ID to filter transactions
    let assetId: String
    
    // Initialize with an AssetViewModel
    init(asset: AssetViewModel) {
        self.asset = asset
        self.assetId = asset.id
        
        // Create a transaction filter predicate for this asset
        let assetIdString = asset.id // Store the id value separately
        let predicate = #Predicate<Transaction> { transaction in
            transaction.asset_id == assetIdString
        }
        
        // Apply the predicate to the @Query using a FetchDescriptor
        // Breaking down the complex initialization to help the compiler
        let sortDescriptor = SortDescriptor(\Transaction.transaction_date, order: .reverse)
        let fetchDescriptor = FetchDescriptor<Transaction>(
            predicate: predicate,
            sortBy: [sortDescriptor]
        )
        _transactions = Query(fetchDescriptor)
        
        // Print initialization info
        print("🏗️ Initializing AssetDetailView for \(asset.name) with ID \(asset.id)")
    }
    
    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()
            
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Layout.spacing * 1.5) {
                    // Current Value Section
                    VStack(alignment: .leading, spacing: 8) {
                        // Total Value Display (prominently displayed)
                        Text("\(FormatHelper.formatCurrency(asset.totalValue)) €")
                            .font(.system(size: 38, weight: .bold, design: .monospaced))
                            .foregroundColor(Theme.Colors.primaryText)
                            .contentTransition(.numericText())
                            .animation(.smooth, value: asset.totalValue)
                        
                        if asset.profitLoss != 0 {
                            HStack(spacing: 4) {
                                Image(systemName: asset.profitLoss >= 0 ? "arrow.up" : "arrow.down")
                                Text("\(FormatHelper.formatCurrency(abs(asset.profitLoss))) €")
                                    .font(.system(.body, design: .monospaced))
                                    .contentTransition(.numericText())
                                    .animation(.smooth, value: asset.profitLoss)
                                Text("(\(FormatHelper.formatPercentage(asset.profitLossPercentage)))")
                                    .font(.system(.body, design: .monospaced))
                                    .contentTransition(.numericText())
                                    .animation(.smooth, value: asset.profitLossPercentage)
                            }
                            .foregroundColor(asset.profitLoss >= 0 ? Theme.Colors.positive : Theme.Colors.negative)
                        }
                    }
                    .padding(.bottom, 10)
                    
                    // Main Content
                    VStack(alignment: .leading, spacing: 24) {
                        // Asset Details Section
                        VStack(alignment: .leading, spacing: 16) {
                            // Section Header
                            Text("Asset Details")
                                .font(Theme.Typography.title3)
                                .foregroundColor(Theme.Colors.primaryText)
                                .padding(.bottom, 4)
                            
                            // Asset Info Group
                            VStack(spacing: 16) {
                                // Symbol & Type
                                HStack {
                                    // Symbol
                                    VStack(alignment: .leading) {
                                        Text("Symbol")
                                            .font(Theme.Typography.caption)
                                            .foregroundColor(Theme.Colors.secondaryText)
                                        Text(asset.symbol)
                                            .font(Theme.Typography.bodyBold)
                                            .foregroundColor(Theme.Colors.primaryText)
                                    }
                                    
                                    Spacer()
                                    
                                    // Type
                                    VStack(alignment: .trailing) {
                                        Text("Type")
                                            .font(Theme.Typography.caption)
                                            .foregroundColor(Theme.Colors.secondaryText)
                                        Text(asset.type.rawValue.capitalized)
                                            .font(Theme.Typography.caption)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Theme.Colors.accent.opacity(0.2))
                                            .cornerRadius(8)
                                            .foregroundColor(Theme.Colors.accent)
                                    }
                                }
                                
                                // Current Price & 24h Change
                                HStack {
                                    // Current Price
                                    VStack(alignment: .leading) {
                                        Text("Current Price")
                                            .font(Theme.Typography.caption)
                                            .foregroundColor(Theme.Colors.secondaryText)
                                        Text("\(FormatHelper.formatCurrency(asset.currentPrice)) €")
                                            .font(.system(.body, design: .monospaced).bold())
                                            .foregroundColor(Theme.Colors.primaryText)
                                            .contentTransition(.numericText())
                                            .animation(.smooth, value: asset.currentPrice)
                                    }
                                    
                                    Spacer()
                                    
                                    // 24h Change
                                    if let change24h = asset.change24h {
                                        VStack(alignment: .trailing) {
                                            Text("24h Change")
                                                .font(Theme.Typography.caption)
                                                .foregroundColor(Theme.Colors.secondaryText)
                                            HStack(spacing: 2) {
                                                Image(systemName: change24h >= 0 ? "arrow.up" : "arrow.down")
                                                Text("\(FormatHelper.formatPercentage(abs(change24h)))")
                                                    .font(.system(.body, design: .monospaced))
                                                    .contentTransition(.numericText())
                                                    .animation(.smooth, value: change24h)
                                            }
                                            .foregroundColor(change24h >= 0 ? Theme.Colors.positive : Theme.Colors.negative)
                                        }
                                    } else {
                                        VStack(alignment: .trailing) {
                                            Text("24h Change")
                                                .font(Theme.Typography.caption)
                                                .foregroundColor(Theme.Colors.secondaryText)
                                            Text("No data")
                                                .font(.system(.body, design: .monospaced))
                                                .foregroundColor(Theme.Colors.secondaryText)
                                        }
                                    }
                                }
                            }
                        }
                        
                        Divider()
                            .background(Theme.Colors.separator)
                            .padding(.vertical, 4)
                        
                        // Position Section
                        VStack(alignment: .leading, spacing: 16) {
                            // Section Header
                            Text("Your Position")
                                .font(Theme.Typography.title3)
                                .foregroundColor(Theme.Colors.primaryText)
                                .padding(.bottom, 4)
                            
                            // Position Stats
                            HStack(spacing: 24) {
                                // Quantity
                                VStack(alignment: .leading) {
                                    Text("Quantity")
                                        .font(Theme.Typography.caption)
                                        .foregroundColor(Theme.Colors.secondaryText)
                                    Text(FormatHelper.formatQuantity(asset.totalQuantity))
                                        .font(.system(.body, design: .monospaced).bold())
                                        .foregroundColor(Theme.Colors.primaryText)
                                        .contentTransition(.numericText())
                                        .animation(.smooth, value: asset.totalQuantity)
                                }
                                
                                Spacer()
                                
                                // Average Price
                                VStack(alignment: .trailing) {
                                    Text("Average Price")
                                        .font(Theme.Typography.caption)
                                        .foregroundColor(Theme.Colors.secondaryText)
                                    Text("\(FormatHelper.formatCurrency(asset.averagePrice)) €")
                                        .font(.system(.body, design: .monospaced).bold())
                                        .foregroundColor(Theme.Colors.primaryText)
                                        .contentTransition(.numericText())
                                        .animation(.smooth, value: asset.averagePrice)
                                }
                            }
                        }
                    }
                    
                    Divider()
                        .background(Theme.Colors.separator)
                        .padding(.vertical, 4)
                    
                    // Transactions Section
                    VStack(alignment: .leading, spacing: 16) {
                        // Section Header
                        Text("Transaction History")
                            .font(Theme.Typography.title3)
                            .foregroundColor(Theme.Colors.primaryText)
                        
                        if transactions.isEmpty {
                            Text("No transactions found for this asset")
                                .font(Theme.Typography.body)
                                .foregroundColor(Theme.Colors.secondaryText)
                                .padding(.top, 8)
                        } else {
                            // Transaction List
                            ForEach(transactions.sorted(by: { $0.transaction_date > $1.transaction_date })) { transaction in
                                VStack(spacing: 0) {
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
                                            
                                            Text(transaction.transaction_date.formatted(date: .abbreviated, time: .shortened))
                                                .font(Theme.Typography.caption)
                                                .foregroundColor(Theme.Colors.secondaryText)
                                        }
                                        
                                        Spacer()
                                        
                                        VStack(alignment: .trailing, spacing: 4) {
                                            Text(transaction.type == .buy ? "+\(FormatHelper.formatQuantity(transaction.quantity))" : "-\(FormatHelper.formatQuantity(transaction.quantity))")
                                                .font(.system(.body, design: .monospaced).bold())
                                                .foregroundColor(Theme.Colors.primaryText)
                                                .contentTransition(.numericText())
                                                .animation(.smooth, value: transaction.quantity)
                                            
                                            Text("\(FormatHelper.formatCurrency(transaction.price_per_unit)) € per unit")
                                                .font(.system(.caption, design: .monospaced))
                                                .foregroundColor(Theme.Colors.secondaryText)
                                                .contentTransition(.numericText())
                                                .animation(.smooth, value: transaction.price_per_unit)
                                        }
                                    }
                                    .padding(.vertical, 12)
                                    .padding(.horizontal, 8)
                                }
                                .background(Theme.Colors.secondaryBackground)
                                .cornerRadius(Theme.Layout.cornerRadius)
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
                .padding(16)
                .background(Theme.Colors.secondaryBackground)
                .cornerRadius(16)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .refreshable {
                await refreshAssetData()
            }
            .overlay(
                isRefreshing ? ProgressView()
                    .tint(Theme.Colors.accent)
                    .scaleEffect(1.0)
                    .frame(width: 50, height: 50)
                    .background(Color.black.opacity(0.1))
                    .cornerRadius(10) : nil
            )
            .onAppear {
                // Refresh data when the view appears
                Task {
                    print("🔄 AssetDetailView appeared for \(asset.name)")
                    await refreshAssetData()
                }
            }
            .onChange(of: transactions.count) { oldCount, newCount in
                // Refresh data whenever the transaction count changes
                print("📈 Transaction count changed from \(oldCount) to \(newCount)")
                if oldCount != newCount {
                    Task {
                        await refreshAssetData()
                    }
                }
            }
        }
        .navigationTitle(asset.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    // Delete button
                    Button {
                        showDeleteAlert = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(Theme.Colors.negative)
                    }
                    
                    // Refresh button
                    Button {
                        Task {
                            await refreshAssetData()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .symbolEffect(.pulse, options: .speed(1.5), value: isRefreshing)
                    }
                    .disabled(isRefreshing)
                }
            }
        }
        .alert("Delete Asset", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    await deleteAsset()
                }
            }
        } message: {
            Text("Are you sure you want to delete this asset? This will also delete all associated transactions and cannot be undone.")
        }
    }
    
    // Function to refresh asset data
    private func refreshAssetData() async {
        // Set refreshing state
        isRefreshing = true
        
        print("🔄 Starting complete asset refresh including API data")
        
        // 1. First, fetch fresh asset data from Supabase if possible
        do {
            // Try to get updated asset data from API (requesting fresh data)
            let assetResponses = try await supabaseManager.fetchAssets()
            print("🌐 Successfully fetched fresh asset data from API")
            
            // Also refresh transactions for this asset (requesting fresh data)
            let transactionResponses = try await supabaseManager.fetchTransactions()
            print("🌐 Successfully fetched fresh transaction data from API")
            
            // Update local SwiftData models on the main thread
            await MainActor.run {
                // Check if the asset still exists in Supabase
                let assetIdForFetch = self.assetId
                let assetStillExists = assetResponses.contains(where: { $0.id == assetIdForFetch })
                
                if !assetStillExists {
                    print("❌ Asset with ID \(assetIdForFetch) no longer exists on server")
                    // We'll let the user continue viewing the asset details but will update UI
                    // to show that the asset has been deleted on the server
                }
                
                // Update assets in SwiftData
                for assetResponse in assetResponses {
                    if let existingAsset = try? modelContext.fetch(FetchDescriptor<Asset>(predicate: #Predicate { $0.id == assetResponse.id })).first {
                        // Update existing asset
                        existingAsset.symbol = assetResponse.symbol
                        existingAsset.name = assetResponse.name
                        existingAsset.isin = assetResponse.isin
                        existingAsset.type = AssetType(rawValue: assetResponse.type) ?? .etf
                        existingAsset.updated_at = Date()
                        print("📝 Updated existing asset in SwiftData: \(existingAsset.name)")
                    }
                }
                
                // Get all transactions for this asset from local database
                let assetTransactionsFetch = FetchDescriptor<Transaction>(predicate: #Predicate { transaction in
                    transaction.asset_id == assetIdForFetch
                })
                let localTransactions = try? modelContext.fetch(assetTransactionsFetch)
                
                // Create set of server transaction IDs
                let apiTransactionIds = Set(transactionResponses.filter { $0.asset_id == assetIdForFetch }.map { $0.id })
                
                // Delete local transactions that no longer exist on server
                if let localTransactions = localTransactions {
                    for transaction in localTransactions {
                        if !apiTransactionIds.contains(transaction.id) {
                            print("🗑️ Deleting transaction that no longer exists on server: \(transaction.id)")
                            modelContext.delete(transaction)
                        }
                    }
                }
                
                // Update transactions in SwiftData
                for transactionResponse in transactionResponses.filter({ $0.asset_id == assetIdForFetch }) {
                    if let existingTransaction = try? modelContext.fetch(FetchDescriptor<Transaction>(predicate: #Predicate { $0.id == transactionResponse.id })).first {
                        // Delete the existing transaction to avoid conflicts
                        modelContext.delete(existingTransaction)
                        print("🗑️ Deleted existing transaction for update: \(existingTransaction.id)")
                    }
                    
                    // Create new transaction
                    let newTransaction = transactionResponse.toTransaction()
                    
                    // Set asset relationship
                    let asset = try? modelContext.fetch(FetchDescriptor<Asset>(predicate: #Predicate { $0.id == assetIdForFetch })).first
                    if let asset = asset {
                        newTransaction.asset = asset
                    }
                    
                    modelContext.insert(newTransaction)
                    print("➕ Inserted updated transaction: \(newTransaction.id)")
                }
                
                // Save changes
                try? modelContext.save()
            }
        } catch {
            print("❌ Error refreshing from API: \(error.localizedDescription). Will continue with local data.")
        }
        
        // 2. Now fetch the asset from SwiftData and get its latest transactions
        if let assetModel = try? modelContext.fetch(FetchDescriptor<Asset>(predicate: #Predicate { $0.id == assetId })).first {
            // Get transactions for this asset
            let transactionsFetch = FetchDescriptor<Transaction>(predicate: #Predicate { transaction in
                transaction.asset_id == assetId
            }, sortBy: [SortDescriptor(\.transaction_date, order: .reverse)])
            
            // Fetch the transactions first to have them available for calculations
            let fetchedTransactions = (try? modelContext.fetch(transactionsFetch)) ?? []
            
            // Convert transactions to view models if needed (but we don't assign to transactions property directly)
            let transactionViewModels = fetchedTransactions.map { transaction in
                TransactionViewModel(
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
            
            // Create an updated asset view model with the latest data
            var updatedAssetViewModel = self.asset
            
            // For savings accounts, process interest rate history
            if assetModel.type == .savings {
                // Get interest rate history from the asset relationship
                let interestRateHistory = assetModel.interestRateHistory
                
                // Process interest rates if needed, but don't try to store them in properties that don't exist
                if !interestRateHistory.isEmpty {
                    let latestRate = interestRateHistory.sorted { $0.start_date > $1.start_date }.first?.rate ?? 0.0
                    // Use the latest rate in our updated view model
                    updatedAssetViewModel.interest_rate = latestRate
                }
            }
            
            // 3. Get a fresh view model with API data for price using the AssetServiceManager
            // Pass the Asset model, not the AssetViewModel
            _ = AssetServiceManager.shared.getAssetViewModel(
                asset: assetModel,
                transactions: fetchedTransactions,
                forceRefresh: true,
                interestRateHistory: assetModel.type == .savings ? assetModel.interestRateHistory : [],
                supabaseManager: supabaseManager,
                onUpdate: { enrichedViewModel in
                    // Update our asset view model with the enriched data on the main thread
                    withAnimation {
                        self.asset = enrichedViewModel
                    }
                }
            )
            
            // Calculate basic metrics while waiting for API data
            if !fetchedTransactions.isEmpty {
                // Calculate total quantity
                let calculatedTotalQuantity = fetchedTransactions.reduce(0) { result, transaction in
                    result + (transaction.type == .buy ? transaction.quantity : -transaction.quantity)
                }
                
                // Calculate total cost
                let calculatedTotalCost = fetchedTransactions.reduce(0) { result, transaction in
                    result + (transaction.type == .buy ? transaction.total_amount : -transaction.total_amount)
                }
                
                if calculatedTotalQuantity > 0 {
                    // Calculate average price
                    let calculatedAveragePrice = calculatedTotalCost / calculatedTotalQuantity
                    
                    // Update with local calculations
                    if calculatedTotalQuantity > 0 {
                        updatedAssetViewModel.totalQuantity = calculatedTotalQuantity
                        updatedAssetViewModel.averagePrice = calculatedAveragePrice
                        
                        // If we have a current price, calculate profit/loss
                        if updatedAssetViewModel.currentPrice > 0 {
                            let currentPrice = updatedAssetViewModel.currentPrice
                            let calculatedProfitLoss = (currentPrice * calculatedTotalQuantity) - calculatedTotalCost
                            let calculatedProfitLossPercentage = calculatedTotalCost > 0 ? 
                                (calculatedProfitLoss / calculatedTotalCost) * 100 : 0
                            
                            updatedAssetViewModel.profitLoss = calculatedProfitLoss
                            updatedAssetViewModel.profitLossPercentage = calculatedProfitLossPercentage
                            updatedAssetViewModel.totalValue = currentPrice * calculatedTotalQuantity
                        }
                        
                        // Update the displayed asset view model with our calculated values
                        self.asset = updatedAssetViewModel
                    }
                }
            }
        }
        
        // Update UI state
        withAnimation {
            isRefreshing = false
        }
    }
    
    // Function to delete an asset
    private func deleteAsset() async {
        // Set refreshing state
        isRefreshing = true
        
        Task {
            do {
                // Delete from Supabase
                try await supabaseManager.deleteAsset(id: assetId)
                
                // If we reach here, deletion was successful
                await MainActor.run {
                    // Delete the asset from SwiftData
                    if let assetToDelete = try? modelContext.fetch(FetchDescriptor<Asset>(predicate: #Predicate { $0.id == assetId })).first {
                        modelContext.delete(assetToDelete)
                        
                        // Delete associated transactions
                        let transactionsToDelete = transactions
                        for transaction in transactionsToDelete {
                            modelContext.delete(transaction)
                        }
                        
                        // Save changes
                        try? modelContext.save()
                        
                        // Navigate back
                        dismiss()
                    }
                }
            } catch {
                print("Error deleting asset: \(error.localizedDescription)")
                
                // Show error message
                await MainActor.run {
                    supabaseManager.setError(error)
                    isRefreshing = false
                }
            }
        }
    }
}

// MARK: - Add Asset View
struct AddAssetView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var supabaseManager: SupabaseManager
    var onComplete: () -> Void
    
    @State private var searchQuery = ""
    @State private var symbol = ""
    @State private var name = ""
    @State private var isin = ""
    @State private var selectedType: AssetType = .etf
    @State private var isAddingAsset = false
    @State private var errorMessage: String?
    @State private var searchResults: [AssetSearchResult] = []
    @State private var isSearching = false
    @State private var searchDebounceTimer: Timer?
    
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
                                    .autocorrectionDisabled(true)
                                    .textInputAutocapitalization(.never)
                                    .onChange(of: searchQuery) { oldValue, newValue in
                                        // Debounce the search
                                        searchDebounceTimer?.invalidate()
                                        
                                        if !newValue.isEmpty && newValue.count >= 2 {
                                            searchDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
                                                searchAssets(query: newValue)
                                            }
                                        } else {
                                            searchResults = []
                                        }
                                    }
                                
                                if isSearching {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                        .padding(.trailing, 8)
                                }
                            }
                            .padding()
                            .background(Theme.Colors.secondaryBackground)
                            .cornerRadius(Theme.Layout.cornerRadius)
                            .padding(.horizontal, Theme.Layout.padding)
                            
                            // Display search results
                            if !searchResults.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(searchResults) { result in
                                        Button(action: {
                                            selectSearchResult(result)
                                        }) {
                                            HStack {
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(result.name)
                                                        .font(Theme.Typography.bodyBold)
                                                        .foregroundColor(Theme.Colors.primaryText)
                                                    
                                                    HStack {
                                                        Text(result.symbol)
                                                            .font(Theme.Typography.caption)
                                                            .foregroundColor(Theme.Colors.secondaryText)
                                                        
                                                        if let exchange = result.exchange, !exchange.isEmpty {
                                                            Text(exchange)
                                                                .font(Theme.Typography.caption)
                                                                .padding(.horizontal, 6)
                                                                .padding(.vertical, 2)
                                                                .background(Theme.Colors.secondaryBackground)
                                                                .cornerRadius(4)
                                                                .foregroundColor(Theme.Colors.secondaryText)
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                        .padding()
                                        .background(Theme.Colors.secondaryBackground)
                                        .cornerRadius(Theme.Layout.cornerRadius)
                                    }
                                }
                                .padding(.horizontal, Theme.Layout.padding)
                            }
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
    
    private func selectSearchResult(_ result: AssetSearchResult) {
        // Auto-fill form fields from search result
        symbol = result.symbol
        name = result.name
        isin = result.isin ?? ""
        
        // Detect asset type based on symbol or exchange
        if result.symbol.contains("BTC") || result.symbol.contains("ETH") || result.symbol.contains("-USD") {
            selectedType = .crypto
        } else {
            selectedType = .etf
        }
        
        // Clear search results and query
        searchQuery = ""
        searchResults = []
    }
    
    private func searchAssets(query: String) {
        guard query.count >= 2 else { return }
        
        isSearching = true
        searchResults = []
        
        Task {
            do {
                // Use the Yahoo Finance API via RapidAPI
                let urlString = "https://apidojo-yahoo-finance-v1.p.rapidapi.com/auto-complete?region=US&q=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query)"
                guard let url = URL(string: urlString) else {
                    throw NSError(domain: "Invalid URL", code: 100, userInfo: nil)
                }
                
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.addValue("apidojo-yahoo-finance-v1.p.rapidapi.com", forHTTPHeaderField: "x-rapidapi-host")
                
                // Get API key from environment variables
                let rapidAPIKey = ProcessInfo.processInfo.environment["RAPIDAPI_KEY"] ?? ""
                if rapidAPIKey.isEmpty {
                    print("Warning: RAPIDAPI_KEY environment variable is not set. Using mock data.")
                    throw NSError(domain: "No API Key", code: 102, userInfo: nil)
                }
                
                request.addValue(rapidAPIKey, forHTTPHeaderField: "x-rapidapi-key")
                
                let (data, response) = try await URLSession.shared.data(for: request)
                
                
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    throw NSError(domain: "Invalid response", code: 101, userInfo: nil)
                }
                
                // Parse the JSON response
                let decoder = JSONDecoder()
                let yahooResponse = try decoder.decode(YahooSearchResponse.self, from: data)
                
                // Map Yahoo Finance quotes to our AssetSearchResult model
                await MainActor.run {
                    searchResults = yahooResponse.quotes.map { quote in
                        AssetSearchResult(
                            id: UUID().uuidString,
                            symbol: quote.symbol,
                            name: quote.longname ?? quote.shortname ?? quote.symbol,
                            exchange: quote.exchDisp,
                            isin: nil // Yahoo API doesn't provide ISIN
                        )
                    }
                    isSearching = false
                }
            } catch {
                print("Error searching Yahoo Finance: \(error.localizedDescription)")
                
                // No fallback data, just show empty results
                await MainActor.run {
                    searchResults = []
                    isSearching = false
                }
            }
        }
    }
}

// MARK: - Yahoo Finance API Models
struct YahooSearchResponse: Decodable {
    let quotes: [YahooQuote]
}

struct YahooQuote: Decodable {
    let symbol: String
    let shortname: String?
    let longname: String?
    let exchDisp: String?
}

// Update the AssetSearchResult to include exchange information
struct AssetSearchResult: Identifiable {
    var id: String
    var symbol: String
    var name: String
    var exchange: String?
    var isin: String?
}

// MARK: - Add Transaction View
struct AddTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var supabaseManager: SupabaseManager
    @Environment(\.modelContext) private var modelContext
    
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
                        VStack(alignment: .leading, spacing: Theme.Layout.spacing) {
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
                            }
                            .padding(.horizontal, Theme.Layout.padding)
                        }
                        
                        // Transaction Details
                        VStack(alignment: .leading, spacing: Theme.Layout.spacing) {
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
                                    Text("Quantity *")
                                        .font(Theme.Typography.caption)
                                        .foregroundColor(Theme.Colors.secondaryText)
                                    
                                    TextField("", text: $quantity)
                                        .keyboardType(.decimalPad)
                                        .padding()
                                        .background(Theme.Colors.secondaryBackground)
                                        .cornerRadius(Theme.Layout.cornerRadius)
                                        .foregroundColor(Theme.Colors.primaryText)
                                        .font(.system(.body, design: .monospaced))
                                        .onChange(of: quantity) { _, newValue in
                                            if let quantityValue = Double(newValue), let priceValue = Double(pricePerUnit) {
                                                totalAmount = FormatHelper.formatCurrency(quantityValue * priceValue)
                                            }
                                        }
                                }
                                
                                // Price per Unit
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Price per Unit *")
                                        .font(Theme.Typography.caption)
                                        .foregroundColor(Theme.Colors.secondaryText)
                                    
                                    TextField("", text: $pricePerUnit)
                                        .keyboardType(.decimalPad)
                                        .padding()
                                        .background(Theme.Colors.secondaryBackground)
                                        .cornerRadius(Theme.Layout.cornerRadius)
                                        .foregroundColor(Theme.Colors.primaryText)
                                        .font(.system(.body, design: .monospaced))
                                        .onChange(of: pricePerUnit) { _, newValue in
                                            if let quantityValue = Double(quantity), let priceValue = Double(newValue) {
                                                totalAmount = FormatHelper.formatCurrency(quantityValue * priceValue)
                                            }
                                        }
                                }
                                
                                // Total Amount (calculated)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Total Amount")
                                        .font(Theme.Typography.caption)
                                        .foregroundColor(Theme.Colors.secondaryText)
                                    
                                    HStack {
                                        Text("\(FormatHelper.formatCurrency(calculatedTotalAmount)) €")
                                            .font(.system(.body, design: .monospaced))
                                            .padding()
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(Theme.Colors.secondaryBackground)
                                            .cornerRadius(Theme.Layout.cornerRadius)
                                            .foregroundColor(Theme.Colors.primaryText)
                                            .contentTransition(.numericText())
                                            .animation(.smooth, value: calculatedTotalAmount)
                                    }
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
        
        // Make sure any previous errors in SupabaseManager are cleared
        supabaseManager.clearError()
        
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
                
                // Check if there was an error set in the SupabaseManager during the operation
                if supabaseManager.hasError {
                    await MainActor.run {
                        errorMessage = supabaseManager.errorMessage
                        isAddingTransaction = false
                    }
                    return
                }
                
                if !transactionId.isEmpty {
                    // Check if the transaction exists in our local database already
                    let fetchDescriptor = FetchDescriptor<Transaction>(predicate: #Predicate { $0.id == transactionId })
                    let existingTransaction = try? modelContext.fetch(fetchDescriptor).first
                    
                    // If not found locally, create it now rather than waiting for a sync
                    if existingTransaction == nil {
                        print("Creating local transaction record to ensure immediate UI update")
                        let newTransaction = Transaction(
                            id: transactionId,
                            asset_id: selectedAsset.id,
                            type: transactionType,
                            quantity: quantityValue,
                            price_per_unit: priceValue, 
                            total_amount: totalAmount,
                            transaction_date: transactionDate,
                            created_at: Date(),
                            updated_at: Date()
                        )
                        
                        // Try to find the asset to establish the relationship 
                        // Extract the ID string from the AssetViewModel to avoid type mismatch in the predicate
                        let assetId = selectedAsset.id
                        let assetFetchDescriptor = FetchDescriptor<Asset>(predicate: #Predicate { $0.id == assetId })
                        if let asset = try? modelContext.fetch(assetFetchDescriptor).first {
                            newTransaction.asset = asset
                            print("Linked new transaction to asset \(asset.name)")
                        }
                        
                        // Insert the transaction into the local database
                        modelContext.insert(newTransaction)
                        try? modelContext.save()
                        print("Successfully saved new transaction locally")
                    }
                    
                    // Transaction was added successfully - call completion and dismiss
                    await MainActor.run {
                        // Make sure the error state is clear
                        supabaseManager.clearError()
                        onComplete()
                        dismiss()
                    }
                } else {
                    // Failed to add transaction
                    await MainActor.run {
                        errorMessage = "Failed to add transaction. Please try again."
                        isAddingTransaction = false
                    }
                }
            } catch {
                // Handle any errors
                await MainActor.run {
                    errorMessage = "Error: \(error.localizedDescription)"
                    isAddingTransaction = false
                }
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

// MARK: - Formatting Helpers
struct FormatHelper {
    // Format currency to show decimals only when needed
    static func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
    
    // Format percentage with one decimal place
    static func formatPercentage(_ value: Double) -> String {
        return String(format: "%.1f%%", value)
    }
    
    // Format quantity - show decimals only when needed
    static func formatQuantity(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(value))"
        } else {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.minimumFractionDigits = 0
            formatter.maximumFractionDigits = 4
            
            return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
        }
    }
}

// Preview
#Preview {
    ContentView()
        .modelContainer(for: [Asset.self, Transaction.self, InterestRateHistory.self], inMemory: true)
        .environmentObject(SupabaseManager.shared)
}
