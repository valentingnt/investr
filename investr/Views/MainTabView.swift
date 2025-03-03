import SwiftUI
import SwiftData

struct MainTabView: View {
    @EnvironmentObject private var supabaseManager: SupabaseManager
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            PortfolioView()
                .environmentObject(supabaseManager)
                .tabItem {
                    Label("Portfolio", systemImage: "chart.pie.fill")
                }
                .tag(0)
            
            TransactionsView()
                .environmentObject(supabaseManager)
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
    }
}

#Preview {
    MainTabView()
        .environmentObject(SupabaseManager.shared)
        .modelContainer(for: [Asset.self, Transaction.self, InterestRateHistory.self])
} 