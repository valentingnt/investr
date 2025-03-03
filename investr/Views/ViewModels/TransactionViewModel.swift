import Foundation

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