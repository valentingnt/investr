import SwiftUI
import SwiftData

struct ContentView: View {
    @StateObject private var supabaseManager = SupabaseManager.shared
    
    var body: some View {
        MainTabView()
            .environmentObject(supabaseManager)
            .onChange(of: supabaseManager.hasError) { _, hasError in
                if hasError {
                    print("Error in SupabaseManager: \(supabaseManager.errorMessage)")
                    // Here you could show a global error alert or toast
                }
            }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Asset.self, Transaction.self, InterestRateHistory.self])
} 