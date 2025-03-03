import SwiftUI

struct PortfolioAssetsListView: View {
    let portfolioItems: [AssetViewModel]
    let portfolioValue: Double
    let isLoading: Bool
    let isRefreshing: Bool
    var namespace: Namespace.ID
    @Binding var displayPerformanceAsPercentage: Bool
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Layout.spacing) {
                // Portfolio Summary Card
                VStack(alignment: .leading, spacing: Theme.Layout.spacing) {
                    HStack {
                        Text("TOTAL ASSETS")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(Theme.Colors.secondaryText)
                        
                        if isLoading || isRefreshing {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                    
                    Text("\(FormatHelper.formatCurrency(portfolioValue)) €")
                        .font(.system(size: 40, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.Colors.primaryText)
                        .contentTransition(.numericText())
                        .transaction { transaction in
                            transaction.animation = .spring(duration: 0.4, bounce: 0.2)
                        }
                    
                    Divider()
                        .background(Theme.Colors.separator)
                        .padding(.vertical, 8)
                    
                    // Portfolio Metrics - Now in vertical layout
                    VStack(spacing: Theme.Layout.spacing) {
                        // Invested Amount
                        HStack {
                            Text("INVESTED")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(Theme.Colors.secondaryText)
                            
                            Spacer()
                            
                            let totalInvested = calculateTotalInvested()
                            Text("\(FormatHelper.formatCurrency(totalInvested)) €")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(Theme.Colors.primaryText)
                        }
                        
                        // Performance
                        HStack {
                            Text("PERFORMANCE")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(Theme.Colors.secondaryText)
                            
                            Spacer()
                            
                            let performance = calculatePerformance()
                            HStack(spacing: 4) {
                                Image(systemName: performance >= 0 ? "arrow.up" : "arrow.down")
                                    .font(.system(size: 12))
                                    .foregroundColor(performance >= 0 ? Theme.Colors.positive : Theme.Colors.negative)
                                Text("\(FormatHelper.formatPercent(performance))")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundColor(performance >= 0 ? Theme.Colors.positive : Theme.Colors.negative)
                            }
                        }
                        
                        // Profit/Loss
                        HStack {
                            Text("PROFIT/LOSS")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(Theme.Colors.secondaryText)
                            
                            Spacer()
                            
                            let profitLoss = portfolioValue - calculateTotalInvested()
                            Text("\(FormatHelper.formatCurrency(profitLoss)) €")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(profitLoss >= 0 ? Theme.Colors.positive : Theme.Colors.negative)
                        }
                    }
                }
                .cardStyle()
                
                // Assets List
                VStack(alignment: .leading, spacing: Theme.Layout.spacing) {
                    HStack {
                        Text("Assets")
                            .font(Theme.Typography.title3)
                            .foregroundColor(Theme.Colors.primaryText)
                        
                        Spacer()
                    }
                    
                    if portfolioItems.isEmpty && !isLoading {
                        emptyStateView
                    } else {
                        assetListView
                    }
                }
            }
            .padding(Theme.Layout.padding)
        }
        .background(Theme.Colors.background)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: Theme.Layout.spacing) {
            Image(systemName: "chart.pie")
                .font(.system(size: 40))
                .foregroundColor(Theme.Colors.accent)
                .padding(.bottom, 8)
            
            Text("No assets yet")
                .font(Theme.Typography.bodyBold)
                .foregroundColor(Theme.Colors.primaryText)
            
            Text("Tap + to add your first investment")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Layout.padding * 2)
    }
    
    private var assetListView: some View {
        VStack(spacing: Theme.Layout.smallSpacing) {
            // Active assets section (quantity > 0) - Remove header
            if !activeAssets.isEmpty {
                ForEach(activeAssets) { asset in
                    NavigationLink(destination: AssetDetailView(asset: asset)
                        .navigationTransition(.zoom(sourceID: "asset-\(asset.id)", in: namespace))
                    ) {
                        AssetRowView(asset: asset, displayPerformanceAsPercentage: displayPerformanceAsPercentage, namespace: namespace)
                    }
                }
            }
            
            // Sold out assets section (quantity = 0) - Make collapsible
            if !soldOutAssets.isEmpty {
                DisclosureGroup(
                    content: {
                        ForEach(soldOutAssets) { asset in
                            NavigationLink(destination: AssetDetailView(asset: asset)
                                .navigationTransition(.zoom(sourceID: "asset-\(asset.id)", in: namespace))
                            ) {
                                AssetRowView(asset: asset, displayPerformanceAsPercentage: displayPerformanceAsPercentage, namespace: namespace)
                            }
                        }
                    },
                    label: {
                        Text("Closed Positions")
                            .font(Theme.Typography.title3)
                            .foregroundColor(Theme.Colors.primaryText)
                            .padding(.vertical, 8)
                    }
                )
                .padding(.top, Theme.Layout.spacing)
            }
            
            if isLoading && portfolioItems.isEmpty {
                ForEach(0..<3, id: \.self) { _ in
                    AssetRowSkeletonView()
                }
            }
        }
    }
    
    // Computed properties for active and sold-out assets
    private var activeAssets: [AssetViewModel] {
        portfolioItems.filter { $0.quantity > 0 }
    }
    
    private var soldOutAssets: [AssetViewModel] {
        portfolioItems.filter { $0.quantity == 0 }
    }
    
    // Helper functions for portfolio metrics
    private func calculateTotalInvested() -> Double {
        // Only count buy transactions for active positions
        portfolioItems.reduce(0) { total, asset in
            if asset.quantity > 0 {
                // For active positions, use quantity * avgPurchasePrice
                return total + (asset.quantity * asset.avgPurchasePrice)
            } else {
                // For closed positions, don't include in total invested
                return total
            }
        }
    }
    
    private func calculatePerformance() -> Double {
        let totalInvested = calculateTotalInvested()
        if totalInvested > 0 {
            return ((portfolioValue - totalInvested) / totalInvested) * 100
        }
        return 0
    }
}

struct AssetRowView: View {
    let asset: AssetViewModel
    let displayPerformanceAsPercentage: Bool
    var namespace: Namespace.ID? = nil
    
    var body: some View {
        HStack(spacing: Theme.Layout.spacing) {
            // Asset Icon
            ZStack {
                Circle()
                    .fill(Theme.Colors.accent.opacity(0.2))
                
                Text(String(asset.symbol.prefix(1)))
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.accent)
            }
            .frame(width: 40, height: 40)
            
            // Asset Info and Value Container
            HStack {
                // Asset Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(asset.name)
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(Theme.Colors.primaryText)
                        .lineLimit(1)
                    
                    Text(asset.symbol)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.secondaryText)
                }
                
                Spacer()
                
                // Asset Value
                VStack(alignment: .trailing, spacing: 4) {
                    if asset.quantity > 0 {
                        Text("\(FormatHelper.formatCurrency(asset.totalValue)) €")
                            .font(Theme.Typography.bodyBold)
                            .foregroundColor(Theme.Colors.primaryText)
                            .contentTransition(.numericText())
                            .transaction { transaction in
                                transaction.animation = .spring(duration: 0.3)
                            }
                    } else {
                        Text("Realized P&L")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.secondaryText)
                    }
                    
                    HStack(spacing: 4) {
                        // Show either percentage or actual value based on preference
                        if displayPerformanceAsPercentage {
                            // Percentage display
                            Image(systemName: asset.percentChange >= 0 ? "arrow.up" : "arrow.down")
                                .font(.system(size: 10))
                                .foregroundColor(asset.percentChange >= 0 ? Theme.Colors.positive : Theme.Colors.negative)
                                .symbolRenderingMode(.hierarchical)
                                .symbolEffect(.variableColor, options: .repeating, value: displayPerformanceAsPercentage)
                            
                            Text("\(FormatHelper.formatPercent(asset.percentChange))")
                                .font(Theme.Typography.caption)
                                .foregroundColor(asset.percentChange >= 0 ? Theme.Colors.positive : Theme.Colors.negative)
                                .contentTransition(.numericText())
                                .transaction { transaction in
                                    transaction.animation = .spring(duration: 0.3)
                                }
                        } else {
                            // Actual value display (P&L in currency)
                            let profitLoss = calculateProfitLoss(asset: asset)
                            
                            Image(systemName: profitLoss >= 0 ? "arrow.up" : "arrow.down")
                                .font(.system(size: 10))
                                .foregroundColor(profitLoss >= 0 ? Theme.Colors.positive : Theme.Colors.negative)
                                .symbolRenderingMode(.hierarchical)
                                .symbolEffect(.variableColor, options: .repeating, value: displayPerformanceAsPercentage)
                            
                            Text("\(FormatHelper.formatCurrency(profitLoss)) €")
                                .font(Theme.Typography.caption)
                                .foregroundColor(profitLoss >= 0 ? Theme.Colors.positive : Theme.Colors.negative)
                                .contentTransition(.numericText())
                                .transaction { transaction in
                                    transaction.animation = .spring(duration: 0.3)
                                }
                        }
                    }
                }
            }
        }
        .padding(Theme.Layout.padding)
        .background(Theme.Colors.secondaryBackground)
        .cornerRadius(Theme.Layout.cornerRadius)
        .if(namespace != nil) { view in
            view.matchedTransitionSource(id: "asset-\(asset.id)", in: namespace!)
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

struct AssetRowSkeletonView: View {
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
        .padding(Theme.Layout.padding)
        .background(Theme.Colors.secondaryBackground)
        .cornerRadius(Theme.Layout.cornerRadius)
    }
}

// Add extension after the last closing brace of the file
// Extension to conditionally apply modifiers
extension View {
    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

#Preview {
    PortfolioAssetsListView(
        portfolioItems: [
            AssetViewModel(
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
        ],
        portfolioValue: 1100,
        isLoading: false,
        isRefreshing: false,
        namespace: Namespace().wrappedValue,
        displayPerformanceAsPercentage: .constant(true)
    )
    .padding()
    .previewLayout(.sizeThatFits)
} 