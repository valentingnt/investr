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
    @State private var portfolioValue: Double = 0
    @State private var portfolioItems: [AssetViewModel] = []
    @State private var selectedTab = 0
    @State private var showingAddAsset = false
    @State private var showingAddTransaction = false
    
    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                portfolioAssetsView
                    .navigationTitle("Portfolio")
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button(action: {
                                showingAddAsset = true
                            }) {
                                Label("Add Asset", systemImage: "plus")
                            }
                        }
                        
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Refresh") {
                                Task {
                                    await loadData()
                                }
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
            }
            .tabItem {
                Label("Portfolio", systemImage: "chart.pie.fill")
            }
            .tag(0)
            
            NavigationStack {
                transactionsView
                    .navigationTitle("Transactions")
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button(action: {
                                showingAddTransaction = true
                            }) {
                                Label("Add Transaction", systemImage: "plus")
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
            }
            .tabItem {
                Label("Transactions", systemImage: "arrow.left.arrow.right")
            }
            .tag(1)
        }
        .task {
            await loadData()
        }
    }
    
    private var portfolioAssetsView: some View {
        ScrollView {
            if isLoading {
                ProgressView()
                    .scaleEffect(1.5)
                    .padding()
            } else {
                VStack(alignment: .leading, spacing: 20) {
                    // Portfolio Summary Card
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Total Portfolio Value")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Text("€\(portfolioValue, specifier: "%.2f")")
                            .font(.system(size: 40, weight: .bold))
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                    
                    // Assets List
                    Text("Assets")
                        .font(.title2)
                        .fontWeight(.bold)
                        .padding(.top)
                    
                    if portfolioItems.isEmpty {
                        Text("No assets found. Add your first asset to get started.")
                            .foregroundColor(.secondary)
                            .padding()
                    } else {
                        ForEach(portfolioItems) { item in
                            NavigationLink(destination: AssetDetailView(asset: item)) {
                                assetRow(item: item)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
                .padding()
            }
        }
    }
    
    private func assetRow(item: AssetViewModel) -> some View {
        VStack {
            HStack(alignment: .center) {
                // Asset Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    HStack(spacing: 8) {
                        Text(item.symbol)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Text(item.type.rawValue.capitalized)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
                
                Spacer()
                
                // Asset Value
                VStack(alignment: .trailing, spacing: 4) {
                    Text("€\(item.totalValue, specifier: "%.2f")")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    HStack(spacing: 4) {
                        Image(systemName: item.profitLoss >= 0 ? "arrow.up" : "arrow.down")
                            .foregroundColor(item.profitLoss >= 0 ? .green : .red)
                            .font(.caption)
                        
                        Text("\(abs(item.profitLossPercentage), specifier: "%.2f")%")
                            .font(.subheadline)
                            .foregroundColor(item.profitLoss >= 0 ? .green : .red)
                    }
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
            
            Divider()
                .padding(.horizontal)
        }
    }
    
    private var transactionsView: some View {
        List {
            if transactions.isEmpty {
                Text("No transactions found.")
                    .foregroundColor(.secondary)
            } else {
                ForEach(transactions) { transaction in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(assets.first(where: { $0.id == transaction.asset_id })?.name ?? "Unknown")
                                .font(.headline)
                            
                            Text(transaction.transaction_date, style: .date)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing) {
                            Text(transaction.type == .buy ? "Buy" : "Sell")
                                .foregroundColor(transaction.type == .buy ? .green : .red)
                                .font(.headline)
                            
                            Text("\(transaction.quantity, specifier: "%.2f") @ €\(transaction.price_per_unit, specifier: "%.2f")")
                                .font(.subheadline)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
    
    private func loadData() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Clear existing data
            for asset in assets {
                modelContext.delete(asset)
            }
            for transaction in transactions {
                modelContext.delete(transaction)
            }
            
            // Fetch data from Supabase
            let assetsResponse = try await supabaseManager.fetchAssets()
            let transactionsResponse = try await supabaseManager.fetchTransactions()
            let interestRateHistoryResponse = try await supabaseManager.fetchInterestRateHistory()
            
            // Convert and save to local database
            for assetResponse in assetsResponse {
                let asset = assetResponse.toAsset()
                modelContext.insert(asset)
            }
            
            for transactionResponse in transactionsResponse {
                let transaction = transactionResponse.toTransaction()
                modelContext.insert(transaction)
            }
            
            for rateResponse in interestRateHistoryResponse {
                let rate = rateResponse.toInterestRateHistory()
                modelContext.insert(rate)
            }
            
            // Calculate portfolio data
            await calculatePortfolioData()
        } catch {
            print("Error loading data: \(error)")
            supabaseManager.error = error
        }
    }
    
    private func calculatePortfolioData() async {
        var items: [AssetViewModel] = []
        var totalValue: Double = 0
        
        for asset in assets {
            let assetTransactions = transactions.filter { $0.asset_id == asset.id }
            
            switch asset.type {
            case .etf:
                let service = ETFService()
                if let enrichedAsset = await service.enrichAssetWithPriceAndTransactions(asset: asset, transactions: assetTransactions) {
                    items.append(enrichedAsset)
                    totalValue += enrichedAsset.totalValue
                }
                
            case .crypto:
                let service = CryptoService()
                if let enrichedAsset = await service.enrichAssetWithPriceAndTransactions(asset: asset, transactions: assetTransactions) {
                    items.append(enrichedAsset)
                    totalValue += enrichedAsset.totalValue
                }
                
            case .savings:
                let service = SavingsService()
                let interestRates = assets.first(where: { $0.id == asset.id })?.interestRateHistory ?? []
                if let enrichedAsset = await service.enrichAssetWithPriceAndTransactions(
                    asset: asset, 
                    transactions: assetTransactions,
                    interestRateHistory: interestRates,
                    supabaseManager: supabaseManager
                ) {
                    items.append(enrichedAsset)
                    totalValue += enrichedAsset.totalValue
                }
            }
        }
        
        portfolioItems = items.sorted(by: { $0.totalValue > $1.totalValue })
        portfolioValue = totalValue
    }
}

// MARK: - Asset Detail View
struct AssetDetailView: View {
    let asset: AssetViewModel
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    VStack(alignment: .leading) {
                        Text(asset.name)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text(asset.symbol)
                            .font(.title3)
                            .foregroundColor(.secondary)
                        
                        Text(asset.type.rawValue.capitalized)
                            .font(.subheadline)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(4)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing) {
                        Text("€\(asset.currentPrice, specifier: "%.2f")")
                            .font(.title)
                            .fontWeight(.bold)
                        
                        if let change24h = asset.change24h {
                            HStack {
                                Image(systemName: change24h >= 0 ? "arrow.up" : "arrow.down")
                                Text("\(abs(change24h), specifier: "%.2f")%")
                            }
                            .foregroundColor(change24h >= 0 ? .green : .red)
                        }
                    }
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.1), radius: 5)
                
                // Portfolio stats
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your Position")
                        .font(.headline)
                    
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Quantity")
                                .foregroundColor(.secondary)
                            Text("\(asset.totalQuantity, specifier: "%.4f")")
                                .font(.title3)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing) {
                            Text("Total Value")
                                .foregroundColor(.secondary)
                            Text("€\(asset.totalValue, specifier: "%.2f")")
                                .font(.title3)
                        }
                    }
                    
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Avg Price")
                                .foregroundColor(.secondary)
                            Text("€\(asset.averagePrice, specifier: "%.2f")")
                                .font(.title3)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing) {
                            Text("P/L")
                                .foregroundColor(.secondary)
                            HStack(spacing: 4) {
                                Text("€\(asset.profitLoss, specifier: "%.2f")")
                                Text("(\(asset.profitLossPercentage, specifier: "%.2f")%)")
                            }
                            .font(.title3)
                            .foregroundColor(asset.profitLoss >= 0 ? .green : .red)
                        }
                    }
                    
                    // Additional asset-specific info
                    if asset.type == .savings, let interestRate = asset.interest_rate {
                        Divider()
                        
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Interest Rate")
                                    .foregroundColor(.secondary)
                                Text("\(interestRate, specifier: "%.2f")%")
                                    .font(.title3)
                            }
                            
                            Spacer()
                            
                            if let accruedInterest = asset.accruedInterest {
                                VStack(alignment: .trailing) {
                                    Text("Accrued Interest")
                                        .foregroundColor(.secondary)
                                    Text("€\(accruedInterest, specifier: "%.2f")")
                                        .font(.title3)
                                        .foregroundColor(.green)
                                }
                            }
                        }
                    }
                    
                    if asset.type == .etf {
                        Divider()
                        
                        if let dayHigh = asset.dayHigh, let dayLow = asset.dayLow {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("Day Range")
                                        .foregroundColor(.secondary)
                                    Text("€\(dayLow, specifier: "%.2f") - €\(dayHigh, specifier: "%.2f")")
                                        .font(.subheadline)
                                }
                                
                                Spacer()
                                
                                if let volume = asset.volume {
                                    VStack(alignment: .trailing) {
                                        Text("Volume")
                                            .foregroundColor(.secondary)
                                        Text("\(volume, specifier: "%.0f")")
                                            .font(.subheadline)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.1), radius: 5)
            }
            .padding()
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
            Form {
                Section(header: Text("Search Asset")) {
                    TextField("Search for an asset...", text: $searchQuery)
                }
                
                Section {
                    TextField("Symbol *", text: $symbol)
                        .autocapitalization(.none)
                    
                    TextField("Name *", text: $name)
                    
                    TextField("ISIN", text: $isin)
                        .autocapitalization(.none)
                    
                    Picker("Type *", selection: $selectedType) {
                        ForEach(types, id: \.self) { type in
                            Text(type.rawValue.capitalized)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }
                
                if let errorMessage = errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                    }
                }
                
                Section {
                    Button(action: addAsset) {
                        if isAddingAsset {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        } else {
                            Text("Add Asset")
                                .frame(maxWidth: .infinity)
                                .foregroundColor(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.black)
                    .cornerRadius(8)
                    .disabled(isAddingAsset || symbol.isEmpty || name.isEmpty)
                }
                .listRowInsets(EdgeInsets())
            }
            .navigationTitle("Add Asset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Back to Dashboard") {
                        dismiss()
                    }
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
                
                if !assetId.isEmpty {
                    // If savings account, automatically add interest rate if needed
                    if selectedType == .savings {
                        // Add a default interest rate of 3% starting today
                        _ = try? await supabaseManager.addInterestRate(
                            assetId: assetId,
                            rate: 3.0,
                            startDate: Date()
                        )
                    }
                    
                    // Refresh data and dismiss
                    onComplete()
                    dismiss()
                } else {
                    errorMessage = "Asset was created but no ID was returned."
                }
            } catch {
                errorMessage = "Error: \(error.localizedDescription)"
            }
            
            isAddingAsset = false
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
            Form {
                Section(header: Text("Asset")) {
                    Picker("Select Asset", selection: $selectedAsset) {
                        Text("Select an asset").tag(nil as AssetViewModel?)
                        ForEach(assets) { asset in
                            Text(asset.name).tag(asset as AssetViewModel?)
                        }
                    }
                }
                
                Section(header: Text("Transaction Details")) {
                    Picker("Type", selection: $transactionType) {
                        Text("Buy").tag(TransactionType.buy)
                        Text("Sell").tag(TransactionType.sell)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    
                    DatePicker("Date", selection: $transactionDate, displayedComponents: .date)
                    
                    TextField("Quantity", text: $quantity)
                        .keyboardType(.decimalPad)
                        .onChange(of: quantity) { _, newValue in
                            if let quantityValue = Double(newValue), let priceValue = Double(pricePerUnit) {
                                totalAmount = "\(quantityValue * priceValue)"
                            }
                        }
                    
                    TextField("Price per Unit", text: $pricePerUnit)
                        .keyboardType(.decimalPad)
                        .onChange(of: pricePerUnit) { _, newValue in
                            if let quantityValue = Double(quantity), let priceValue = Double(newValue) {
                                totalAmount = "\(quantityValue * priceValue)"
                            }
                        }
                    
                    HStack {
                        Text("Total Amount")
                        Spacer()
                        Text("€\(calculatedTotalAmount, specifier: "%.2f")")
                            .foregroundColor(.secondary)
                    }
                }
                
                if let errorMessage = errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                    }
                }
                
                Section {
                    Button(action: addTransaction) {
                        if isAddingTransaction {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        } else {
                            Text("Add Transaction")
                                .frame(maxWidth: .infinity)
                                .foregroundColor(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.black)
                    .cornerRadius(8)
                    .disabled(isAddingTransaction || selectedAsset == nil || quantity.isEmpty || pricePerUnit.isEmpty)
                }
                .listRowInsets(EdgeInsets())
            }
            .navigationTitle("Add Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func addTransaction() {
        guard let selectedAsset = selectedAsset,
              let quantityValue = Double(quantity),
              let priceValue = Double(pricePerUnit) else {
            errorMessage = "Please fill in all required fields."
            return
        }
        
        isAddingTransaction = true
        errorMessage = nil
        
        let totalAmount = quantityValue * priceValue
        
        Task {
            do {
                // Create a new transaction in Supabase
                _ = try await supabaseManager.addTransaction(
                    assetId: selectedAsset.id,
                    type: transactionType,
                    quantity: quantityValue,
                    pricePerUnit: priceValue,
                    totalAmount: totalAmount,
                    date: transactionDate
                )
                
                // Refresh data and dismiss
                onComplete()
                dismiss()
            } catch {
                errorMessage = "Error: \(error.localizedDescription)"
            }
            
            isAddingTransaction = false
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
    
    // Optional fields based on asset type
    var change24h: Double?
    var dayHigh: Double?
    var dayLow: Double?
    var previousClose: Double?
    var volume: Double?
    var interest_rate: Double?
    var accruedInterest: Double?
    
    // Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: AssetViewModel, rhs: AssetViewModel) -> Bool {
        lhs.id == rhs.id
    }
}

// Preview
#Preview {
    ContentView()
        .modelContainer(for: [Asset.self, Transaction.self, InterestRateHistory.self], inMemory: true)
        .environmentObject(SupabaseManager.shared)
}
