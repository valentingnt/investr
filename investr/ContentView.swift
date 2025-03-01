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
    @State private var namespace = Namespace().wrappedValue
    
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
                            Task {
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
                                    .navigationTitle(item.name)
                                    .navigationBarTitleDisplayMode(.large)
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
                                        .navigationTitle(item.name)
                                        .navigationBarTitleDisplayMode(.large)
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
            .padding(Theme.Layout.padding)
            .background(Theme.Colors.secondaryBackground)
            .cornerRadius(Theme.Layout.cornerRadius)
        }
        .padding(.vertical, 4)
    }
    
    private func loadData() async {
        // Cancel any existing refresh task
        isLoading = true
        isRefreshing = true
        
        // Cancel any existing refresh task
        refreshTask?.cancel()
        
        refreshTask = Task {
            do {
                // Fetch assets and transactions from Supabase API
                print("Starting to fetch data from API...")
                
                // Fetch and save assets
                print("Fetching assets from API...")
                let assetResponses = try await supabaseManager.fetchAssets()
                print("Successfully fetched \(assetResponses.count) assets from API")
                
                // Fetch and save transactions
                print("Fetching transactions from API...")
                let transactionResponses = try await supabaseManager.fetchTransactions()
                print("Successfully fetched \(transactionResponses.count) transactions from API")
                
                // Update local SwiftData models
                await MainActor.run {
                    print("Updating local SwiftData models...")
                    
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
                print("Error loading data: \(error)")
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
    
    // Update the loadAssetsIndependently method to include transactions in the view model
    private func loadAssetsIndependently(oldItems: [AssetViewModel] = []) async {
        // Create new list for portfolio items
        var items: [AssetViewModel] = []
        var totalPortfolioValue: Double = 0
        
        print("Starting to load \(assets.count) assets independently")
        
        // Process each asset independently
        for (index, asset) in assets.enumerated() {
            // Skip if the task was cancelled
            if Task.isCancelled { 
                print("Task was cancelled, stopping asset loading")
                break 
            }
            
            print("Processing asset \(index + 1)/\(assets.count): \(asset.name) (\(asset.symbol)) of type \(asset.type)")
            
            // Get transactions for this specific asset
            let assetTransactions = transactions.filter { $0.asset_id == asset.id }
            print("Found \(assetTransactions.count) transactions for \(asset.name)")
            
            // Convert the transactions to view models for display
            let transactionViewModels = assetTransactions.map { convertToTransactionViewModel(transaction: $0) }
            
            // Use a dedicated task for each asset to isolate any failures
            do {
                // Create a new task for each asset to isolate failures
                let enrichedAsset = try await withTimeout(seconds: 15) {
                    // Process each asset type independently
                    switch asset.type {
                    case .etf:
                        print("Enriching ETF asset: \(asset.name)")
                        let service = ETFService()
                        return await service.enrichAssetWithPriceAndTransactions(
                            asset: asset, 
                            transactions: assetTransactions
                        )
                        
                    case .crypto:
                        print("Enriching Crypto asset: \(asset.name)")
                        let service = CryptoService()
                        return await service.enrichAssetWithPriceAndTransactions(
                            asset: asset, 
                            transactions: assetTransactions
                        )
                        
                    case .savings:
                        print("Enriching Savings asset: \(asset.name)")
                        let service = SavingsService()
                        let interestRates = assets.first(where: { $0.id == asset.id })?.interestRateHistory ?? []
                        return await service.enrichAssetWithPriceAndTransactions(
                            asset: asset, 
                            transactions: assetTransactions,
                            interestRateHistory: interestRates,
                            supabaseManager: supabaseManager
                        )
                    }
                }
                
                // If we got data for this asset, add it to our results and include transactions
                if let enrichedAsset = enrichedAsset {
                    print("Successfully enriched asset: \(enrichedAsset.name) with value: \(enrichedAsset.totalValue)")
                    
                    // Create a mutable copy of the asset
                    var mutableAsset = enrichedAsset
                    // Add the transaction view models to the asset
                    mutableAsset.transactions = transactionViewModels
                    mutableAsset.hasTransactions = !transactionViewModels.isEmpty
                    
                    items.append(mutableAsset)
                    totalPortfolioValue += mutableAsset.totalValue
                    
                    // Update the UI with this asset immediately to show progress
                    await MainActor.run {
                        withAnimation(.smooth) {
                            // Find existing item by ID
                            if let index = portfolioItems.firstIndex(where: { $0.id == asset.id }) {
                                // Update existing item
                                portfolioItems[index] = mutableAsset
                            } else {
                                // Add new item
                                portfolioItems.append(mutableAsset)
                            }
                            
                            // Keep portfolio items sorted by value
                            portfolioItems = portfolioItems.sorted(by: { $0.totalValue > $1.totalValue })
                            
                            // Update portfolio total value
                            portfolioValue = portfolioItems.reduce(0) { $0 + $1.totalValue }
                        }
                    }
                } else {
                    print("⚠️ Failed to enrich asset: \(asset.name) (\(asset.symbol)) of type \(asset.type)")
                    
                    // Try to find this asset in old items to preserve it if possible
                    if let oldAsset = oldItems.first(where: { $0.id == asset.id }) {
                        print("Preserving previous data for \(asset.name)")
                        items.append(oldAsset)
                        totalPortfolioValue += oldAsset.totalValue
                        
                        // Update UI with the preserved old asset
                        await MainActor.run {
                            withAnimation(.smooth) {
                                if !portfolioItems.contains(where: { $0.id == oldAsset.id }) {
                                    portfolioItems.append(oldAsset)
                                    portfolioItems = portfolioItems.sorted(by: { $0.totalValue > $1.totalValue })
                                    portfolioValue = portfolioItems.reduce(0) { $0 + $1.totalValue }
                                }
                            }
                        }
                    }
                }
                
            } catch {
                // Log the error but continue processing other assets
                print("⚠️ Error loading asset \(asset.name): \(error.localizedDescription)")
                
                // Try to find this asset in old items to preserve it if possible
                if let oldAsset = oldItems.first(where: { $0.id == asset.id }) {
                    print("Error occurred but preserving previous data for \(asset.name)")
                    items.append(oldAsset)
                    totalPortfolioValue += oldAsset.totalValue
                    
                    // Update UI with the preserved old asset
                    await MainActor.run {
                        withAnimation(.smooth) {
                            if !portfolioItems.contains(where: { $0.id == oldAsset.id }) {
                                portfolioItems.append(oldAsset)
                                portfolioItems = portfolioItems.sorted(by: { $0.totalValue > $1.totalValue })
                                portfolioValue = portfolioItems.reduce(0) { $0 + $1.totalValue }
                            }
                        }
                    }
                }
            }
        }
        
        print("Finished loading \(items.count) of \(assets.count) assets. Portfolio value: \(totalPortfolioValue)")
        
        // Final UI update with all results
        await MainActor.run {
            withAnimation(.smooth) {
                // We now only remove items that no longer exist in the dataset
                let loadedAssetIds = items.map { $0.id }
                
                // Only remove items that are no longer in the data
                // This allows us to preserve previously loaded items that failed to load this time
                let itemsToRemove = portfolioItems.filter { !loadedAssetIds.contains($0.id) }
                for item in itemsToRemove {
                    if let index = portfolioItems.firstIndex(where: { $0.id == item.id }) {
                        portfolioItems.remove(at: index)
                    }
                }
                
                // Ensure items are sorted by value
                portfolioItems = portfolioItems.sorted(by: { $0.totalValue > $1.totalValue })
                
                // Only recalculate the final portfolio value if we have new items
                if !items.isEmpty {
                    portfolioValue = portfolioItems.reduce(0) { $0 + $1.totalValue }
                }
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
}

// MARK: - Asset Detail View
struct AssetDetailView: View {
    let asset: AssetViewModel
    
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
                        
                        Divider()
                            .background(Theme.Colors.separator)
                            .padding(.vertical, 4)
                        
                        // Transactions Section
                        VStack(alignment: .leading, spacing: 16) {
                            // Section Header
                            Text("Transaction History")
                                .font(Theme.Typography.title3)
                                .foregroundColor(Theme.Colors.primaryText)
                            
                            if asset.transactions.isEmpty {
                                Text("No transactions found for this asset")
                                    .font(Theme.Typography.body)
                                    .foregroundColor(Theme.Colors.secondaryText)
                                    .padding(.top, 8)
                            } else {
                                // Transaction List
                                ForEach(asset.transactions.sorted(by: { $0.date > $1.date })) { transaction in
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
                                                
                                                Text(transaction.date.formatted(date: .abbreviated, time: .shortened))
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
                                                
                                                Text("\(FormatHelper.formatCurrency(transaction.price)) € per unit")
                                                    .font(.system(.caption, design: .monospaced))
                                                    .foregroundColor(Theme.Colors.secondaryText)
                                                    .contentTransition(.numericText())
                                                    .animation(.smooth, value: transaction.price)
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
                }
                .padding(16)
            }
        }
        .navigationTitle(asset.name)
        .navigationBarTitleDisplayMode(.large)
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
                                                Spacer()
                                            }
                                            .padding()
                                            .background(Theme.Colors.secondaryBackground)
                                            .cornerRadius(Theme.Layout.cornerRadius)
                                        }
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
                                        Text("\(FormatHelper.formatCurrency(calculatedTotalAmount)) €")
                                            .font(.system(.title3, design: .monospaced).bold())
                                            .foregroundColor(Theme.Colors.primaryText)
                                            .contentTransition(.numericText())
                                            .animation(.smooth, value: calculatedTotalAmount)
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
