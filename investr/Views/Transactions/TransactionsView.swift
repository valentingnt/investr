import SwiftUI
import SwiftData

struct TransactionsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var supabaseManager: SupabaseManager
    
    @Query private var transactions: [Transaction]
    @Query private var assets: [Asset]
    
    @State private var showingAddTransaction = false
    @State private var portfolioItems: [AssetViewModel] = []
    @State private var isLoading = false
    @State private var transactionToDelete: Transaction? = nil
    @State private var showingDeleteConfirmation = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                if transactions.isEmpty && !isLoading {
                    emptyStateView
                } else {
                    List {
                        ForEach(transactionsByDate.keys.sorted(by: >), id: \.self) { date in
                            Section(header: 
                                Text(formatDate(date))
                                    .font(Theme.Typography.captionBold)
                                    .foregroundColor(Theme.Colors.secondaryText)
                            ) {
                                ForEach(transactionsByDate[date] ?? []) { transaction in
                                    TransactionRowView(transaction: transaction)
                                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                        .listRowBackground(Theme.Colors.secondaryBackground)
                                        .swipeActions(edge: .trailing) {
                                            Button(role: .destructive) {
                                                transactionToDelete = transaction
                                                showingDeleteConfirmation = true
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                }
                            }
                        }
                        
                        if isLoading && transactions.isEmpty {
                            // Show skeleton loading views in a section
                            Section {
                                ForEach(0..<3, id: \.self) { _ in
                                    TransactionSkeletonView()
                                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                        .listRowBackground(Theme.Colors.secondaryBackground)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .background(Theme.Colors.background)
                }
            }
            .background(Theme.Colors.background)
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
                        await loadPortfolioData()
                    }
                }
                .environmentObject(supabaseManager)
            }
            .confirmationDialog(
                "Delete Transaction",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let transaction = transactionToDelete {
                        deleteTransaction(transaction)
                    }
                }
                Button("Cancel", role: .cancel) {
                    transactionToDelete = nil
                }
            } message: {
                Text("Are you sure you want to delete this transaction? This action cannot be undone.")
            }
            .refreshable {
                await loadPortfolioData()
            }
        }
        .task {
            await loadPortfolioData()
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: Theme.Layout.spacing) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 40))
                .foregroundColor(Theme.Colors.accent)
                .padding(.bottom, 8)
            
            Text("No transactions yet")
                .font(Theme.Typography.bodyBold)
                .foregroundColor(Theme.Colors.primaryText)
            
            Text("Tap + to add your first transaction")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Layout.padding * 2)
    }
    
    private var transactionsByDate: [Date: [Transaction]] {
        Dictionary(grouping: transactions) { transaction in
            Calendar.current.startOfDay(for: transaction.transaction_date)
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    private func loadPortfolioData() async {
        isLoading = true
        defer { isLoading = false }
        
        // Create array of AssetViewModels from the assets in the database
        await MainActor.run {
            portfolioItems = []
            
            for asset in assets {
                // Get transactions for this specific asset
                let assetTransactions = transactions.filter { $0.asset_id == asset.id }
                
                // Calculate basic metrics
                let buyTransactions = assetTransactions.filter { $0.type == .buy }
                let sellTransactions = assetTransactions.filter { $0.type == .sell }
                
                let totalBought = buyTransactions.reduce(0) { $0 + $1.quantity }
                let totalSold = sellTransactions.reduce(0) { $0 + $1.quantity }
                let quantity = totalBought - totalSold
                
                let totalCost = buyTransactions.reduce(0) { $0 + $1.total_amount }
                let avgPurchasePrice = totalBought > 0 ? totalCost / totalBought : 0
                
                // For simplicity, use the average purchase price as the current price
                // In a real app, you would get the current price from an API
                let currentPrice = avgPurchasePrice
                let totalValue = quantity * currentPrice
                let percentChange = 0.0 // Can't calculate without real-time prices
                
                let viewModel = AssetViewModel(
                    id: asset.id,
                    symbol: asset.symbol,
                    name: asset.name,
                    type: asset.type,
                    quantity: quantity,
                    avgPurchasePrice: avgPurchasePrice,
                    currentPrice: currentPrice,
                    totalValue: totalValue,
                    percentChange: percentChange,
                    transactions: assetTransactions
                )
                
                portfolioItems.append(viewModel)
            }
        }
    }
    
    private func deleteTransaction(_ transaction: Transaction) {
        Task {
            do {
                // Delete from Supabase
                let success = try await supabaseManager.deleteTransaction(id: transaction.id)
                
                if success {
                    await MainActor.run {
                        // Delete from SwiftData
                        modelContext.delete(transaction)
                        
                        // Refresh data
                        Task {
                            await loadPortfolioData()
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
        }
    }
}

struct TransactionRowView: View {
    let transaction: Transaction
    
    var body: some View {
        HStack(spacing: Theme.Layout.spacing) {
            // Transaction Icon
            ZStack {
                Circle()
                    .fill(transactionColor.opacity(0.2))
                    .frame(width: 40, height: 40)
                
                Image(systemName: transaction.type == .buy ? "arrow.down" : "arrow.up")
                    .font(.system(size: 16))
                    .foregroundColor(transactionColor)
            }
            
            // Transaction Details
            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.asset?.name ?? "Unknown Asset")
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.primaryText)
                
                Text(transaction.asset?.symbol ?? "")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.secondaryText)
            }
            
            Spacer()
            
            // Transaction Amount
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(transaction.type == .buy ? "+" : "-") \(FormatHelper.formatQuantity(transaction.quantity))")
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.primaryText)
                
                Text("\(FormatHelper.formatCurrency(transaction.total_amount)) €")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.secondaryText)
            }
        }
        .padding(Theme.Layout.smallSpacing)
    }
    
    private var transactionColor: Color {
        transaction.type == .buy ? Theme.Colors.positive : Theme.Colors.negative
    }
}

struct TransactionSkeletonView: View {
    var body: some View {
        HStack(spacing: Theme.Layout.spacing) {
            Circle()
                .fill(Theme.Colors.secondaryText.opacity(0.2))
                .frame(width: 40, height: 40)
            
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.Colors.secondaryText.opacity(0.2))
                    .frame(width: 120, height: 16)
                
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.Colors.secondaryText.opacity(0.2))
                    .frame(width: 80, height: 12)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.Colors.secondaryText.opacity(0.2))
                    .frame(width: 80, height: 16)
                
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.Colors.secondaryText.opacity(0.2))
                    .frame(width: 60, height: 12)
            }
        }
        .padding(Theme.Layout.smallSpacing)
    }
}

#Preview {
    TransactionsView()
        .environmentObject(SupabaseManager.shared)
        .modelContainer(for: [Asset.self, Transaction.self, InterestRateHistory.self])
} 