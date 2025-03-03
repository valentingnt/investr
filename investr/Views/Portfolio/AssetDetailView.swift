import SwiftUI
import SwiftData

struct AssetDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var supabaseManager: SupabaseManager
    @AppStorage("displayPerformanceAsPercentage") private var displayPerformanceAsPercentage: Bool = true
    let asset: AssetViewModel
    
    @State private var isLoading = false
    @State private var showingAddTransaction = false
    @State private var showingDeleteConfirmation = false
    @State private var assetTransactions: [Transaction] = []
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Layout.spacing) {
                // Asset Header and Current Value Container - This will zoom from the list
                VStack(alignment: .leading, spacing: Theme.Layout.spacing) {
                    // Asset Header
                    VStack(alignment: .leading, spacing: Theme.Layout.smallSpacing) {
                        HStack {
                            Text(asset.name)
                                .font(Theme.Typography.title2)
                                .foregroundColor(Theme.Colors.primaryText)
                                .lineLimit(2)
                                .minimumScaleFactor(0.9)
                            
                            Spacer()
                            
                            assetTypeTag
                        }
                        
                        Text(asset.symbol)
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.secondaryText)
                    }
                    
                    // Current Value
                    VStack(alignment: .leading, spacing: Theme.Layout.smallSpacing) {
                        Text(asset.quantity > 0 ? "Current Value" : "Final Performance")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.secondaryText)
                        
                        if asset.quantity > 0 {
                            Text("\(FormatHelper.formatCurrency(asset.totalValue)) €")
                                .font(Theme.Typography.largePrice)
                                .foregroundColor(Theme.Colors.primaryText)
                                .contentTransition(.numericText())
                                .transaction { transaction in
                                    transaction.animation = .spring(duration: 0.3)
                                }
                        }
                    }
                }
                
                // Holding Summary
                VStack(alignment: .leading, spacing: Theme.Layout.smallSpacing) {
                    Text("Holding Summary")
                        .font(Theme.Typography.title3)
                        .foregroundColor(Theme.Colors.primaryText)
                    
                    HStack {
                        detailItem(title: "Quantity", value: FormatHelper.formatQuantity(asset.quantity))
                        Spacer()
                        detailItem(title: "Avg. Purchase", value: "\(FormatHelper.formatCurrency(asset.avgPurchasePrice)) €")
                        Spacer()
                        detailItem(title: "Current Price", value: "\(FormatHelper.formatCurrency(asset.currentPrice)) €")
                    }
                }
                .padding()
                .background(Theme.Colors.secondaryBackground)
                .cornerRadius(Theme.Layout.cornerRadius)
                
                // Transactions
                VStack(alignment: .leading, spacing: Theme.Layout.smallSpacing) {
                    HStack {
                        Text("Transactions")
                            .font(Theme.Typography.title3)
                            .foregroundColor(Theme.Colors.primaryText)
                        
                        Spacer()
                        
                        Button(action: {
                            showingAddTransaction = true
                        }) {
                            Image(systemName: "plus")
                                .foregroundColor(Theme.Colors.accent)
                        }
                    }
                    
                    if asset.transactions.isEmpty {
                        Text("No transactions yet")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.secondaryText)
                            .padding()
                    } else {
                        // Sort transactions by date - newest first
                        ForEach(asset.transactions.sorted(by: { $0.transaction_date > $1.transaction_date })) { transaction in
                            TransactionRowView(transaction: transaction)
                        }
                    }
                }
                .padding()
                .background(Theme.Colors.secondaryBackground)
                .cornerRadius(Theme.Layout.cornerRadius)
                
                // Delete Button
                Button(action: {
                    showingDeleteConfirmation = true
                }) {
                    HStack {
                        Spacer()
                        Text("Delete Asset")
                            .font(Theme.Typography.bodyBold)
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .padding()
                    .background(Color.red)
                    .cornerRadius(Theme.Layout.cornerRadius)
                }
                .padding(.top, Theme.Layout.spacing)
            }
            .padding(Theme.Layout.padding)
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .navigationTitle("Asset Details")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    dismiss()
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .foregroundColor(Theme.Colors.accent)
                }
            }
        }
        .sheet(isPresented: $showingAddTransaction) {
            AddTransactionView(assets: [asset]) {
                // Reload data after adding a transaction
                Task {
                    // Reload the asset details
                }
            }
            .environmentObject(supabaseManager)
        }
        .alert("Delete Asset", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    await deleteAsset()
                }
            }
        } message: {
            Text("Are you sure you want to delete this asset? This will remove all associated transactions and cannot be undone.")
        }
    }
    
    private var assetTypeTag: some View {
        HStack(spacing: 4) {
            switch asset.type {
            case .etf:
                Image(systemName: "chart.pie.fill")
                Text("ETF")
            case .crypto:
                Image(systemName: "bitcoinsign")
                Text("Crypto")
            case .savings:
                Image(systemName: "banknote")
                Text("Savings")
            }
        }
        .font(Theme.Typography.caption)
        .foregroundColor(Theme.Colors.accent)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Theme.Colors.accent.opacity(0.2))
        .cornerRadius(12)
    }
    
    private func detailItem(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.secondaryText)
            
            Text(value)
                .font(Theme.Typography.bodyBold)
                .foregroundColor(Theme.Colors.primaryText)
                .contentTransition(.numericText())
                .transaction { transaction in
                    transaction.animation = .spring(duration: 0.3, bounce: 0.2)
                }
        }
    }
    
    // Function to delete an asset
    private func deleteAsset() async {
        // Set loading state
        isLoading = true
        
        Task {
            do {
                // Delete from Supabase
                try await supabaseManager.deleteAsset(id: asset.id)
                
                // If we reach here, deletion was successful
                await MainActor.run {
                    // Delete the asset from SwiftData
                    let assetID = asset.id // Store asset.id as a String variable
                    let assetPredicate = #Predicate<Asset> { asset in
                        asset.id == assetID
                    }
                    
                    if let assetToDelete = try? modelContext.fetch(FetchDescriptor(predicate: assetPredicate)).first {
                        modelContext.delete(assetToDelete)
                        
                        // Delete associated transactions
                        let transactionPredicate = #Predicate<Transaction> { transaction in
                            transaction.asset_id == assetID
                        }
                        
                        let transactionsToDelete = try? modelContext.fetch(FetchDescriptor(predicate: transactionPredicate))
                        
                        for transaction in transactionsToDelete ?? [] {
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
                    isLoading = false
                    supabaseManager.setError(error)
                }
            }
        }
    }
    
    // Helper to calculate the actual profit/loss value
    private func calculateProfitLoss(asset: AssetViewModel) -> Double {
        if asset.quantity > 0 {
            // For active positions: current value - cost basis
            return (asset.quantity * asset.currentPrice) - (asset.quantity * asset.avgPurchasePrice)
        } else if !asset.transactions.isEmpty {
            // For closed positions: total sell value - total buy cost
            let buyTransactions = asset.transactions.filter { $0.type == .buy }
            let sellTransactions = asset.transactions.filter { $0.type == .sell }
            
            let totalBuyCost = buyTransactions.reduce(0) { $0 + $1.total_amount }
            let totalSellValue = sellTransactions.reduce(0) { $0 + $1.total_amount }
            
            return totalSellValue - totalBuyCost
        }
        return 0
    }
}

#Preview {
    NavigationStack {
        AssetDetailView(
            asset: AssetViewModel(
                id: "1",
                symbol: "VWCE",
                name: "Vanguard FTSE All-World ETF",
                type: .etf,
                quantity: 10,
                avgPurchasePrice: 100,
                currentPrice: 110,
                totalValue: 1100,
                percentChange: 10.0,
                transactions: []
            )
        )
    }
    .environmentObject(SupabaseManager.shared)
} 
