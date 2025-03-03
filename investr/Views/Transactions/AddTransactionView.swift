import SwiftUI
import SwiftData

struct AddTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var supabaseManager: SupabaseManager
    
    // Focus state for keyboard navigation
    enum Field: Int, Hashable {
        case quantity, pricePerUnit, totalAmount
    }
    @FocusState private var focusedField: Field?
    
    let assets: [AssetViewModel]
    var onTransactionAdded: (() -> Void)?
    
    @State private var selectedAsset: AssetViewModel?
    @State private var transactionType: TransactionType = .buy
    @State private var quantity = ""
    @State private var pricePerUnit = ""
    @State private var totalAmount = ""
    @State private var transactionDate = Date()
    @State private var isCreating = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    // Animation state
    @State private var animateTotal = false
    
    // Computed properties for validation
    private var quantityValue: Double? {
        return Double(quantity.replacingOccurrences(of: ",", with: "."))
    }
    
    private var pricePerUnitValue: Double? {
        return Double(pricePerUnit.replacingOccurrences(of: ",", with: "."))
    }
    
    private var totalAmountValue: Double? {
        return Double(totalAmount.replacingOccurrences(of: ",", with: "."))
    }
    
    private var canCreateTransaction: Bool {
        guard let asset = selectedAsset else { return false }
        
        // For savings, only require total amount
        if asset.type == .savings {
            return totalAmountValue != nil && totalAmountValue! > 0
        }
        
        // For ETF and crypto, require quantity and either price per unit or total amount
        return quantityValue != nil && quantityValue! > 0 &&
               (pricePerUnitValue != nil || totalAmountValue != nil)
    }
    
    // Utility function to convert Double to String without adding ".0"
    private func cleanNumber(_ value: Double) -> String {
        let intValue = Int(value)
        if Double(intValue) == value {
            return "\(intValue)" // Return integer without decimal
        } else {
            // Use string interpolation but avoid any automatic formatting
            return "\(value)"
        }
    }
    
    // Utility function to move to next field
    private func moveToNextField() {
        switch focusedField {
        case .quantity:
            focusedField = .pricePerUnit
        case .pricePerUnit:
            focusedField = .totalAmount
        case .totalAmount:
            focusedField = nil
        case nil:
            break
        }
    }
    
    // Utility function to move to previous field
    private func moveToPreviousField() {
        switch focusedField {
        case .quantity:
            focusedField = nil
        case .pricePerUnit:
            focusedField = .quantity
        case .totalAmount:
            focusedField = .pricePerUnit
        case nil:
            break
        }
    }
    
    // Custom text field with toolbar
    private func FormTextField(
        title: String,
        text: Binding<String>,
        field: Field,
        suffix: String? = nil,
        useNumericTransition: Bool = false
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            
            if useNumericTransition {
                // Special case for numeric transition
                TextField("0.00", text: text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .contentTransition(.numericText())
                    .focused($focusedField, equals: field)
            } else {
                // Standard field without transition
                TextField("0.00", text: text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .focused($focusedField, equals: field)
            }
            
            if let suffix = suffix {
                Text(suffix)
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // Asset selection
                Section(header: Text("Asset")) {
                    if assets.isEmpty {
                        Text("No assets available. Add an asset first.")
                            .foregroundColor(Theme.Colors.secondaryText)
                    } else {
                        Picker("Select Asset", selection: $selectedAsset) {
                            Text("Select an asset").tag(nil as AssetViewModel?)
                            ForEach(assets) { asset in
                                Text(asset.name).tag(asset as AssetViewModel?)
                            }
                        }
                        .pickerStyle(.navigationLink)
                    }
                }
                
                if let asset = selectedAsset {
                    // Transaction type
                    Section(header: Text("Transaction Type")) {
                        Picker("Type", selection: $transactionType) {
                            Text("Buy").tag(TransactionType.buy)
                            Text("Sell").tag(TransactionType.sell)
                        }
                        .pickerStyle(.segmented)
                    }
                    
                    // Transaction details
                    Section(header: Text("Transaction Details")) {
                        // For non-savings assets, show quantity
                        if asset.type != .savings {
                            FormTextField(title: "Quantity", text: $quantity, field: .quantity)
                                .onChange(of: quantity) { oldValue, newValue in
                                    if let qty = quantityValue, let price = pricePerUnitValue {
                                        // Calculate total without any formatting
                                        let newTotal = qty * price
                                        
                                        // Convert without adding ".0"
                                        totalAmount = cleanNumber(newTotal)
                                    }
                                }
                            
                            FormTextField(title: "Price per Unit", text: $pricePerUnit, field: .pricePerUnit)
                                .onChange(of: pricePerUnit) { oldValue, newValue in
                                    if let qty = quantityValue, let price = pricePerUnitValue {
                                        // Calculate total without any formatting
                                        let newTotal = qty * price
                                        
                                        // Convert without adding ".0"
                                        totalAmount = cleanNumber(newTotal)
                                    }
                                }
                        }
                        
                        FormTextField(title: "Total Amount", text: $totalAmount, field: .totalAmount, suffix: "€", useNumericTransition: true)
                            .onChange(of: totalAmount) { oldValue, newValue in
                                if asset.type != .savings {
                                    if let total = totalAmountValue, let qty = quantityValue, qty > 0 {
                                        // Calculate price without any formatting
                                        let newPrice = total / qty
                                        
                                        // Convert without adding ".0"
                                        pricePerUnit = cleanNumber(newPrice)
                                    }
                                }
                            }
                        
                        DatePicker(
                            "Date",
                            selection: $transactionDate,
                            displayedComponents: [.date]
                        )
                    }
                    
                    // Action button
                    Section {
                        Button(action: {
                            createTransaction()
                        }) {
                            HStack {
                                Spacer()
                                Text("Add Transaction")
                                    .font(Theme.Typography.bodyBold)
                                    .foregroundColor(.white)
                                Spacer()
                            }
                        }
                        .padding()
                        .background(canCreateTransaction ? Theme.Colors.accent : Color.gray)
                        .cornerRadius(Theme.Layout.cornerRadius)
                        .disabled(!canCreateTransaction || isCreating)
                    }
                }
            }
            .navigationTitle("Add Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                // Add a single keyboard toolbar for all text fields
                ToolbarItemGroup(placement: .keyboard) {
                    Button(action: moveToPreviousField) {
                        Image(systemName: "chevron.up")
                    }
                    .disabled(focusedField == .quantity || focusedField == nil)
                    
                    Button(action: moveToNextField) {
                        Image(systemName: "chevron.down")
                    }
                    .disabled(focusedField == .totalAmount || focusedField == nil)
                    
                    Spacer()
                    
                    Button("Done") {
                        focusedField = nil
                    }
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
    
    private func createTransaction() {
        guard let asset = selectedAsset, canCreateTransaction else { return }
        
        isCreating = true
        
        Task {
            do {
                let qty: Double
                let priceUnit: Double
                let total: Double
                
                if asset.type == .savings {
                    // For savings, quantity is 1 and price per unit is the total amount
                    qty = 1.0
                    total = totalAmountValue ?? 0
                    priceUnit = total
                } else {
                    // For other assets, use the entered values
                    qty = quantityValue ?? 0
                    priceUnit = pricePerUnitValue ?? 0
                    total = totalAmountValue ?? (qty * priceUnit)
                }
                
                // First, save to Supabase (this happens on a background thread)
                let transactionId = try await supabaseManager.addTransaction(
                    assetId: asset.id, 
                    type: transactionType, 
                    quantity: qty, 
                    pricePerUnit: priceUnit, 
                    totalAmount: total, 
                    date: transactionDate
                )
                
                // Switch to the main thread for UI updates and model context changes
                await MainActor.run {
                    // Create the transaction in the model context
                    let transaction = Transaction(
                        id: transactionId,  // Use the ID from Supabase
                        asset_id: asset.id,
                        type: transactionType,
                        quantity: qty,
                        price_per_unit: priceUnit,
                        total_amount: total,
                        transaction_date: transactionDate,
                        created_at: Date(),
                        updated_at: Date()
                    )
                    
                    // Find the asset in the database and link the transaction
                    let assetID = asset.id // Store the ID as a local variable
                    if let dbAsset = try? modelContext.fetch(FetchDescriptor<Asset>(predicate: #Predicate { asset in
                        asset.id == assetID
                    })).first {
                        transaction.asset = dbAsset
                        dbAsset.transactions.append(transaction)
                    }
                    
                    modelContext.insert(transaction)
                    
                    // Call the completion handler
                    onTransactionAdded?()
                    
                    // Dismiss the sheet
                    dismiss()
                    
                    // Reset loading state
                    isCreating = false
                }
            } catch {
                // Handle error - make sure this also happens on the main thread
                await MainActor.run {
                    errorMessage = "Failed to add transaction: \(error.localizedDescription)"
                    showError = true
                    isCreating = false
                }
            }
        }
    }
}

#Preview {
    AddTransactionView(
        assets: [
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
        ]
    ) { }
    .environmentObject(SupabaseManager.shared)
} 