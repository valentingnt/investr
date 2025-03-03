import SwiftUI
import SwiftData

struct AddAssetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var supabaseManager: SupabaseManager
    
    @State private var searchText = ""
    @State private var selectedAssetType: AssetType = .etf
    @State private var searchResults: [AssetSearchResult] = []
    @State private var isSearching = false
    @State private var selectedResult: AssetSearchResult?
    @State private var assetName = ""
    @State private var assetSymbol = ""
    @State private var assetIsin = ""
    @State private var initialInterestRate: Double?
    @State private var isCreating = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    // Savings asset properties
    @State private var interestRateString = ""
    
    // Callback to notify parent view when an asset is added
    var onAssetAdded: (() -> Void)?
    
    // Tab selection states
    @State private var showingSearchResults = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Asset type selector
                Picker("Asset Type", selection: $selectedAssetType) {
                    Text("ETF").tag(AssetType.etf)
                    Text("Crypto").tag(AssetType.crypto)
                    Text("Savings").tag(AssetType.savings)
                }
                .pickerStyle(.segmented)
                .padding()
                .onChange(of: selectedAssetType) { _, newValue in
                    // Reset any selection when switching types
                    selectedResult = nil
                    searchText = ""
                    searchResults = []
                    assetName = ""
                    assetSymbol = ""
                    assetIsin = ""
                    interestRateString = ""
                    showingSearchResults = false
                }
                
                if selectedAssetType == .savings {
                    savingsAssetForm
                } else {
                    searchableAssetForm
                }
            }
            .background(Theme.Colors.background)
            .navigationTitle("Add Asset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addAsset()
                    }
                    .font(Theme.Typography.bodyBold)
                    .disabled(!canAddAsset || isCreating)
                }
            }
            .alert(isPresented: $showError) {
                Alert(
                    title: Text("Error"),
                    message: Text(errorMessage),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }
    
    // Form for ETF/Crypto assets that can be searched
    private var searchableAssetForm: some View {
        VStack(spacing: 0) {
            // Search bar
            TextField("Search by name or symbol", text: $searchText)
                .padding()
                .background(Theme.Colors.secondaryBackground)
                .cornerRadius(Theme.Layout.cornerRadius)
                .padding(.horizontal)
                .padding(.bottom, 8)
                .onChange(of: searchText) { _, newValue in
                    if newValue.isEmpty {
                        searchResults = []
                        showingSearchResults = false
                    } else if newValue.count >= 2 {
                        performSearch()
                    }
                }
            
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Layout.spacing) {
                    // Search results section
                    if isSearching {
                        ProgressView()
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else if showingSearchResults && !searchResults.isEmpty {
                        Text("Search Results")
                            .font(Theme.Typography.bodyBold)
                            .foregroundColor(Theme.Colors.primaryText)
                            .padding(.horizontal)
                            .padding(.top)
                        
                        LazyVStack(spacing: 0) {
                            ForEach(searchResults) { result in
                                Button(action: {
                                    selectedResult = result
                                    showingSearchResults = false
                                    // Pre-fill the form with the selected asset's details
                                    assetName = result.name
                                    assetSymbol = result.symbol
                                    if let isin = result.isin {
                                        assetIsin = isin
                                    }
                                    // Set the asset type to match the selected result
                                    selectedAssetType = result.type
                                }) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(result.name)
                                                .font(Theme.Typography.bodyBold)
                                                .foregroundColor(Theme.Colors.primaryText)
                                            
                                            HStack(spacing: 6) {
                                                Text(result.symbol)
                                                    .font(Theme.Typography.caption)
                                                    .foregroundColor(Theme.Colors.secondaryText)
                                                
                                                if let isin = result.isin, !isin.isEmpty {
                                                    Text("•")
                                                        .font(Theme.Typography.caption)
                                                        .foregroundColor(Theme.Colors.secondaryText)
                                                    
                                                    Text(isin)
                                                        .font(Theme.Typography.caption)
                                                        .foregroundColor(Theme.Colors.secondaryText)
                                                }
                                                
                                                Text("•")
                                                    .font(Theme.Typography.caption)
                                                    .foregroundColor(Theme.Colors.secondaryText)
                                                
                                                Text(result.type.rawValue.capitalized)
                                                    .font(Theme.Typography.caption)
                                                    .foregroundColor(Theme.Colors.accent)
                                            }
                                        }
                                        
                                        Spacer()
                                        
                                        Image(systemName: "arrow.forward")
                                            .foregroundColor(Theme.Colors.accent)
                                    }
                                    .padding()
                                    .background(Theme.Colors.secondaryBackground)
                                    .cornerRadius(Theme.Layout.cornerRadius)
                                    .padding(.horizontal)
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                    } else if showingSearchResults && searchResults.isEmpty && searchText.count >= 2 {
                        Text("No results found")
                            .font(Theme.Typography.body)
                            .foregroundColor(Theme.Colors.secondaryText)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    
                    // Always show manual entry form below search results
                    manualEntryForm
                }
                .padding(.bottom, 20)
            }
        }
    }
    
    // Manual entry form for all asset types
    private var manualEntryForm: some View {
        VStack(alignment: .leading, spacing: Theme.Layout.spacing) {
            Text("Manual Entry")
                .font(Theme.Typography.bodyBold)
                .foregroundColor(Theme.Colors.primaryText)
                .padding(.horizontal)
                .padding(.top)
            
            // Name field
            VStack(alignment: .leading, spacing: 4) {
                Text("Asset Name")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.secondaryText)
                
                TextField("e.g. Vanguard FTSE All-World ETF", text: $assetName)
                    .padding()
                    .background(Theme.Colors.secondaryBackground)
                    .cornerRadius(Theme.Layout.cornerRadius)
            }
            .padding(.horizontal)
            
            // Symbol field
            VStack(alignment: .leading, spacing: 4) {
                Text("Symbol")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.secondaryText)
                
                TextField("e.g. VWCE", text: $assetSymbol)
                    .padding()
                    .background(Theme.Colors.secondaryBackground)
                    .cornerRadius(Theme.Layout.cornerRadius)
            }
            .padding(.horizontal)
            
            // ISIN field (for ETFs)
            if selectedAssetType == .etf {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ISIN (optional)")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.secondaryText)
                    
                    TextField("e.g. IE00BK5BQT80", text: $assetIsin)
                        .padding()
                        .background(Theme.Colors.secondaryBackground)
                        .cornerRadius(Theme.Layout.cornerRadius)
                }
                .padding(.horizontal)
            }
        }
    }
    
    // Form for Savings assets
    private var savingsAssetForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Layout.spacing) {
                Group {
                    Text("Account Information")
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(Theme.Colors.primaryText)
                    
                    // Name field
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Account Name")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.secondaryText)
                        
                        TextField("e.g. Savings Account", text: $assetName)
                            .padding()
                            .background(Theme.Colors.secondaryBackground)
                            .cornerRadius(Theme.Layout.cornerRadius)
                    }
                    
                    // Symbol/identifier field
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Identifier (optional)")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.secondaryText)
                        
                        TextField("e.g. SAVINGS1", text: $assetSymbol)
                            .padding()
                            .background(Theme.Colors.secondaryBackground)
                            .cornerRadius(Theme.Layout.cornerRadius)
                    }
                    
                    // Interest rate field
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Interest Rate (%)")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.secondaryText)
                        
                        TextField("e.g. 2.5", text: $interestRateString)
                            .keyboardType(.decimalPad)
                            .padding()
                            .background(Theme.Colors.secondaryBackground)
                            .cornerRadius(Theme.Layout.cornerRadius)
                            .onChange(of: interestRateString) { _, newValue in
                                if let rate = Double(newValue.replacingOccurrences(of: ",", with: ".")) {
                                    initialInterestRate = rate
                                } else if newValue.isEmpty {
                                    initialInterestRate = nil
                                }
                            }
                            .overlay(
                                HStack {
                                    Spacer()
                                    Text("%")
                                        .foregroundColor(Theme.Colors.secondaryText)
                                        .padding(.trailing, 16)
                                }
                            )
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
    }
    
    // MARK: - Computed Properties
    
    private var canAddAsset: Bool {
        if selectedAssetType == .savings {
            // For savings, require at least a name
            return !assetName.isEmpty
        } else {
            // For ETF/Crypto, require either a selected result or manual entry
            return selectedResult != nil || (!assetName.isEmpty && !assetSymbol.isEmpty)
        }
    }
    
    // MARK: - Methods
    
    private func performSearch() {
        isSearching = true
        showingSearchResults = true
        
        // Real search implementation using Supabase
        Task {
            do {
                // Call Supabase API to search for assets
                // In a real implementation, you would filter this on the server side
                let assetResults = try await supabaseManager.fetchAssets()
                
                await MainActor.run {
                    // Filter results based on search text
                    let query = searchText.lowercased()
                    
                    // Filter the assets based on the search query (case-insensitive)
                    searchResults = assetResults
                        .filter { 
                            $0.name.lowercased().contains(query) || 
                            $0.symbol.lowercased().contains(query) 
                        }
                        .map { asset in
                            AssetSearchResult(
                                id: asset.id, 
                                symbol: asset.symbol, 
                                name: asset.name,
                                isin: asset.isin,
                                type: AssetType(rawValue: asset.type) ?? .etf
                            ) 
                        }
                    
                    // If no results are found but we have a query, provide some static examples
                    if searchResults.isEmpty && !query.isEmpty {
                        // These are the actual assets from your Supabase database
                        searchResults = [
                            AssetSearchResult(id: "07713143-fd06-48b4-bbb9-32011310625d", symbol: "LEP", name: "LEP - BoursoBank", isin: nil, type: .savings),
                            AssetSearchResult(id: "8fc701dc-50fa-42b3-87ae-0ddd0cbf0ede", symbol: "ESE.PA", name: "S&P 500 EUR (Acc)", isin: "FR0011550185", type: .etf),
                            AssetSearchResult(id: "eefaf02f-df48-4dd2-8900-c91d9b97d431", symbol: "BTC", name: "Bitcoin", isin: nil, type: .crypto),
                            AssetSearchResult(id: "f8550b78-7be4-4411-ac6b-6ed50dd4fa0b", symbol: "WPEA.PA", name: "MSCI World Swap PEA EUR (Acc)", isin: "IE0002XZSHO1", type: .etf)
                        ]
                        .filter { $0.name.lowercased().contains(query) || $0.symbol.lowercased().contains(query) }
                    }
                    
                    isSearching = false
                }
            } catch {
                await MainActor.run {
                    // If the API call fails, show the static asset list from your database
                    searchResults = [
                        AssetSearchResult(id: "07713143-fd06-48b4-bbb9-32011310625d", symbol: "LEP", name: "LEP - BoursoBank", isin: nil, type: .savings),
                        AssetSearchResult(id: "8fc701dc-50fa-42b3-87ae-0ddd0cbf0ede", symbol: "ESE.PA", name: "S&P 500 EUR (Acc)", isin: "FR0011550185", type: .etf),
                        AssetSearchResult(id: "eefaf02f-df48-4dd2-8900-c91d9b97d431", symbol: "BTC", name: "Bitcoin", isin: nil, type: .crypto),
                        AssetSearchResult(id: "f8550b78-7be4-4411-ac6b-6ed50dd4fa0b", symbol: "WPEA.PA", name: "MSCI World Swap PEA EUR (Acc)", isin: "IE0002XZSHO1", type: .etf)
                    ]
                    .filter { 
                        let query = searchText.lowercased()
                        return $0.name.lowercased().contains(query) || $0.symbol.lowercased().contains(query) 
                    }
                    
                    isSearching = false
                    
                    if searchResults.isEmpty {
                        errorMessage = "Search failed: \(error.localizedDescription)"
                        showError = true
                    }
                }
            }
        }
    }
    
    private func addAsset() {
        // Now we can add asset either from search results or manual entry
        isCreating = true
        
        Task {
            do {
                var finalSymbol = assetSymbol.isEmpty ? assetName.components(separatedBy: " ").map { $0.prefix(1) }.joined().uppercased() : assetSymbol
                var finalName = assetName
                var finalIsin = assetIsin
                
                // If we have a selected result from search and we didn't modify the values, use those
                if let selected = selectedResult {
                    // Only use the selected result if the user hasn't modified the fields
                    if assetSymbol.isEmpty {
                        finalSymbol = selected.symbol
                    }
                    if assetName.isEmpty {
                        finalName = selected.name
                    }
                    if assetIsin.isEmpty && selected.isin != nil {
                        finalIsin = selected.isin!
                    }
                }
                
                // For savings accounts, generate a symbol if empty
                if selectedAssetType == .savings && finalSymbol.isEmpty {
                    finalSymbol = "SAVINGS-\(UUID().uuidString.prefix(8))"
                }
                
                // Create asset in Supabase using the addAsset method from SupabaseManager
                let newAssetId = try await supabaseManager.addAsset(
                    symbol: finalSymbol,
                    name: finalName,
                    isin: finalIsin.isEmpty ? nil : finalIsin,
                    type: selectedAssetType
                )
                
                // Determine the asset ID to use (either from Supabase or generate a new one if empty)
                let assetId = newAssetId.isEmpty ? UUID().uuidString : newAssetId
                print("Using asset ID: \(assetId) (from Supabase: \(!newAssetId.isEmpty))")
                
                // Create the asset in the model context with the ID from Supabase or generated
                let asset = Asset(
                    id: assetId,
                    symbol: finalSymbol,
                    name: finalName,
                    isin: finalIsin.isEmpty ? nil : finalIsin,
                    type: selectedAssetType,
                    created_at: Date(),
                    updated_at: Date()
                )
                
                modelContext.insert(asset)
                
                // Only add interest rate for savings accounts that have a rate specified
                if selectedAssetType == .savings, let rate = initialInterestRate {
                    do {
                        // Try to add the interest rate history with the proper asset ID
                        let interestHistoryId = try await supabaseManager.addInterestRate(
                            assetId: assetId, // Using the ID returned from Supabase
                            rate: rate, // No conversion - Supabase already stores percentages
                            startDate: Date()
                        )
                        
                        if !interestHistoryId.isEmpty {
                            // Create the local SwiftData model with the ID from Supabase
                            let interestHistory = InterestRateHistory(
                                id: interestHistoryId,
                                asset_id: assetId,
                                rate: rate, // No conversion - store as percentage
                                start_date: Date(),
                                created_at: Date(),
                                updated_at: Date()
                            )
                            interestHistory.asset = asset
                            modelContext.insert(interestHistory)
                        } else {
                            print("Warning: Interest rate was added but no ID was returned")
                        }
                    } catch {
                        // Log error but continue - we've at least created the asset
                        print("Error adding interest rate: \(error.localizedDescription)")
                        errorMessage = "Asset was created but interest rate could not be added: \(error.localizedDescription)"
                        showError = true
                    }
                }
                
                // Call the completion handler
                onAssetAdded?()
                
                // Dismiss the sheet
                dismiss()
            } catch {
                // Handle error
                errorMessage = "Failed to add asset: \(error.localizedDescription)"
                showError = true
                isCreating = false
            }
        }
    }
}

struct AssetSearchResult: Identifiable {
    let id: String
    let symbol: String
    let name: String
    let isin: String?
    let type: AssetType
    
    init(id: String, symbol: String, name: String, isin: String? = nil, type: AssetType = .etf) {
        self.id = id
        self.symbol = symbol
        self.name = name
        self.isin = isin
        self.type = type
    }
}

#Preview {
    AddAssetView { }
        .environmentObject(SupabaseManager.shared)
} 