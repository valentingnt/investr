//
//  Item.swift
//  investr
//
//  Created by Valentin Genest on 28/02/2025.
//

import Foundation
import SwiftData

// MARK: - Asset Model
@Model
final class Asset {
    @Attribute(.unique) var id: String
    var symbol: String
    var name: String
    var isin: String?
    var type: AssetType
    var created_at: Date
    var updated_at: Date
    
    // Relationships
    @Relationship(deleteRule: .cascade, inverse: \Transaction.asset)
    var transactions: [Transaction] = []
    
    @Relationship(deleteRule: .cascade, inverse: \InterestRateHistory.asset)
    var interestRateHistory: [InterestRateHistory] = []
    
    init(id: String, symbol: String, name: String, isin: String? = nil, type: AssetType, 
         created_at: Date, updated_at: Date) {
        self.id = id
        self.symbol = symbol
        self.name = name
        self.isin = isin
        self.type = type
        self.created_at = created_at
        self.updated_at = updated_at
    }
}

enum AssetType: String, Codable {
    case etf
    case crypto
    case savings
}

// MARK: - Transaction Model
@Model
final class Transaction {
    @Attribute(.unique) var id: String
    var asset_id: String
    var type: TransactionType
    var quantity: Double
    var price_per_unit: Double
    var total_amount: Double
    var transaction_date: Date
    var created_at: Date
    var updated_at: Date
    
    // Relationships
    var asset: Asset?
    
    init(id: String, asset_id: String, type: TransactionType, quantity: Double, 
         price_per_unit: Double, total_amount: Double, transaction_date: Date, 
         created_at: Date, updated_at: Date) {
        self.id = id
        self.asset_id = asset_id
        self.type = type
        self.quantity = quantity
        self.price_per_unit = price_per_unit
        self.total_amount = total_amount
        self.transaction_date = transaction_date
        self.created_at = created_at
        self.updated_at = updated_at
    }
}

enum TransactionType: String, Codable {
    case buy
    case sell
}

// MARK: - Interest Rate History Model
@Model
final class InterestRateHistory {
    @Attribute(.unique) var id: String
    var asset_id: String
    var rate: Double
    var start_date: Date
    var end_date: Date?
    var created_at: Date
    var updated_at: Date
    
    // Relationships
    var asset: Asset?
    
    init(id: String, asset_id: String, rate: Double, start_date: Date, 
         end_date: Date? = nil, created_at: Date, updated_at: Date) {
        self.id = id
        self.asset_id = asset_id
        self.rate = rate
        self.start_date = start_date
        self.end_date = end_date
        self.created_at = created_at
        self.updated_at = updated_at
    }
}
