//
//  investrApp.swift
//  investr
//
//  Created by Valentin Genest on 28/02/2025.
//

import SwiftUI
import SwiftData
import Supabase

@main
struct investrApp: App {
    // Supabase client
    @StateObject private var supabaseManager = SupabaseManager.shared
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Asset.self,
            Transaction.self,
            InterestRateHistory.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(supabaseManager)
        }
        .modelContainer(sharedModelContainer)
    }
}

// MARK: - Supabase Insert Models
struct AssetInsert: Encodable {
    let symbol: String
    let name: String
    let isin: String?
    let type: String
}

struct TransactionInsert: Encodable {
    let asset_id: String
    let type: String
    let quantity: Double
    let price_per_unit: Double
    let total_amount: Double
    let transaction_date: String
}

struct InterestRateInsert: Encodable {
    let asset_id: String
    let rate: Double
    let start_date: String
    let end_date: String?
}

// MARK: - Supabase Manager
class SupabaseManager: ObservableObject {
    static let shared = SupabaseManager()
    
    let client: SupabaseClient
    
    @Published var isLoading = false
    @Published var error: Error?
    
    private init() {
        guard let supabaseUrl = ProcessInfo.processInfo.environment["SUPABASE_URL"],
              let supabaseKey = ProcessInfo.processInfo.environment["SUPABASE_KEY"] else {
            fatalError("Supabase URL or Key not found in environment variables")
        }
        
        self.client = SupabaseClient(
            supabaseURL: URL(string: supabaseUrl)!,
            supabaseKey: supabaseKey
        )
    }
    
    // MARK: - Assets Functions
    func fetchAssets() async throws -> [AssetResponse] {
        let response = try await client
            .from("assets")
            .select()
            .execute()
        
        let data = response.data
        return try JSONDecoder().decode([AssetResponse].self, from: data)
    }
    
    func addAsset(symbol: String, name: String, isin: String?, type: AssetType) async throws -> String {
        let assetData = AssetInsert(
            symbol: symbol,
            name: name,
            isin: isin,
            type: type.rawValue
        )
        
        let response = try await client
            .from("assets")
            .insert(assetData)
            .execute()
        
        if response.status >= 200 && response.status < 300 {
            // Try to extract the ID of the newly created asset
            do {
                let assets = try JSONDecoder().decode([AssetResponse].self, from: response.data)
                if let newAsset = assets.first {
                    return newAsset.id
                }
            } catch {
                print("Error decoding asset response: \(error)")
            }
            
            // If we couldn't get the ID, return success but empty string
            return ""
        } else {
            throw NSError(
                domain: "SupabaseManager",
                code: response.status,
                userInfo: [NSLocalizedDescriptionKey: "Failed to add asset: Status \(response.status)"]
            )
        }
    }
    
    // MARK: - Transactions Functions
    func fetchTransactions() async throws -> [TransactionResponse] {
        let response = try await client
            .from("transactions")
            .select()
            .execute()
        
        let data = response.data
        return try JSONDecoder().decode([TransactionResponse].self, from: data)
    }
    
    func addTransaction(assetId: String, type: TransactionType, quantity: Double, 
                         pricePerUnit: Double, totalAmount: Double, date: Date) async throws -> String {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        let transactionData = TransactionInsert(
            asset_id: assetId,
            type: type.rawValue,
            quantity: quantity,
            price_per_unit: pricePerUnit,
            total_amount: totalAmount,
            transaction_date: dateFormatter.string(from: date)
        )
        
        let response = try await client
            .from("transactions")
            .insert(transactionData)
            .execute()
        
        if response.status >= 200 && response.status < 300 {
            // Try to extract the ID of the newly created transaction
            do {
                let transactions = try JSONDecoder().decode([TransactionResponse].self, from: response.data)
                if let newTransaction = transactions.first {
                    return newTransaction.id
                }
            } catch {
                print("Error decoding transaction response: \(error)")
            }
            
            // If we couldn't get the ID, return success but empty string
            return ""
        } else {
            throw NSError(
                domain: "SupabaseManager",
                code: response.status,
                userInfo: [NSLocalizedDescriptionKey: "Failed to add transaction: Status \(response.status)"]
            )
        }
    }
    
    // MARK: - Interest Rate History Functions
    func fetchInterestRateHistory() async throws -> [InterestRateHistoryResponse] {
        let response = try await client
            .from("interest_rate_history")
            .select()
            .execute()
        
        let data = response.data
        return try JSONDecoder().decode([InterestRateHistoryResponse].self, from: data)
    }
    
    func getCurrentInterestRate(assetId: String) async throws -> Double? {
        let response = try await client
            .rpc("get_current_interest_rate", params: ["asset_uuid": assetId])
            .execute()
        
        let data = response.data
        return try JSONDecoder().decode(Double?.self, from: data)
    }
    
    func addInterestRate(assetId: String, rate: Double, startDate: Date, endDate: Date? = nil) async throws -> String {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        let interestRateData = InterestRateInsert(
            asset_id: assetId,
            rate: rate,
            start_date: dateFormatter.string(from: startDate),
            end_date: endDate != nil ? dateFormatter.string(from: endDate!) : nil
        )
        
        let response = try await client
            .from("interest_rate_history")
            .insert(interestRateData)
            .execute()
        
        if response.status >= 200 && response.status < 300 {
            // Try to extract the ID of the newly created interest rate
            do {
                let rates = try JSONDecoder().decode([InterestRateHistoryResponse].self, from: response.data)
                if let newRate = rates.first {
                    return newRate.id
                }
            } catch {
                print("Error decoding interest rate response: \(error)")
            }
            
            // If we couldn't get the ID, return success but empty string
            return ""
        } else {
            throw NSError(
                domain: "SupabaseManager",
                code: response.status,
                userInfo: [NSLocalizedDescriptionKey: "Failed to add interest rate: Status \(response.status)"]
            )
        }
    }
}

// MARK: - Supabase Response Models
struct AssetResponse: Codable {
    let id: String
    let symbol: String
    let name: String
    let isin: String?
    let type: String
    let created_at: String
    let updated_at: String
    
    func toAsset() -> Asset {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        return Asset(
            id: id,
            symbol: symbol,
            name: name,
            isin: isin,
            type: AssetType(rawValue: type) ?? .etf,
            created_at: dateFormatter.date(from: created_at) ?? Date(),
            updated_at: dateFormatter.date(from: updated_at) ?? Date()
        )
    }
}

struct TransactionResponse: Codable {
    let id: String
    let asset_id: String
    let type: String
    let quantity: Double
    let price_per_unit: Double
    let total_amount: Double
    let transaction_date: String
    let created_at: String
    let updated_at: String
    
    func toTransaction() -> Transaction {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        return Transaction(
            id: id,
            asset_id: asset_id,
            type: TransactionType(rawValue: type) ?? .buy,
            quantity: quantity,
            price_per_unit: price_per_unit,
            total_amount: total_amount,
            transaction_date: dateFormatter.date(from: transaction_date) ?? Date(),
            created_at: dateFormatter.date(from: created_at) ?? Date(),
            updated_at: dateFormatter.date(from: updated_at) ?? Date()
        )
    }
}

struct InterestRateHistoryResponse: Codable {
    let id: String
    let asset_id: String
    let rate: Double
    let start_date: String
    let end_date: String?
    let created_at: String
    let updated_at: String
    
    func toInterestRateHistory() -> InterestRateHistory {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        return InterestRateHistory(
            id: id,
            asset_id: asset_id,
            rate: rate,
            start_date: dateFormatter.date(from: start_date) ?? Date(),
            end_date: end_date != nil ? dateFormatter.date(from: end_date!) : nil,
            created_at: dateFormatter.date(from: created_at) ?? Date(),
            updated_at: dateFormatter.date(from: updated_at) ?? Date()
        )
    }
}
