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
    @Published var errorMessage: String = ""
    @Published var hasError: Bool = false
    private let requestTimeout: TimeInterval = 30 // 30 seconds timeout
    private var customURLSession: URLSession
    
    private init() {
        guard let supabaseUrl = ProcessInfo.processInfo.environment["SUPABASE_URL"],
              let supabaseKey = ProcessInfo.processInfo.environment["SUPABASE_KEY"] else {
            fatalError("Supabase URL or Key not found in environment variables")
        }
        
        // Create a custom URLSession configuration with timeout and better cancellation handling
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = requestTimeout * 2
        configuration.waitsForConnectivity = true
        self.customURLSession = URLSession(configuration: configuration)
        
        self.client = SupabaseClient(
            supabaseURL: URL(string: supabaseUrl)!,
            supabaseKey: supabaseKey
        )
    }
    
    // Helper method to set error and related properties
    func setError(_ error: Error) {
        self.error = error
        self.errorMessage = error.localizedDescription
        self.hasError = true
        print("Error set: \(errorMessage)")
    }
    
    // Helper method to clear error state
    func clearError() {
        self.error = nil
        self.errorMessage = ""
        self.hasError = false
    }
    
    // MARK: - Assets Functions
    func fetchAssets() async throws -> [AssetResponse] {
        do {
            // Check for cancellation before making the request
            try Task.checkCancellation()
            
            print("Starting to fetch assets...")
            
            // Use the custom URLSession for this request if possible
            let response = try await client
                .from("assets")
                .select()
                .execute()
            
            // Check for cancellation after getting response, before parsing
            try Task.checkCancellation()
            
            print("Successfully received assets data")
            let data = response.data
            let assets = try JSONDecoder().decode([AssetResponse].self, from: data)
            print("Successfully decoded \(assets.count) assets")
            return assets
        } catch let error as CancellationError {
            print("Asset fetch was cancelled")
            throw error
        } catch {
            print("Error fetching assets: \(error.localizedDescription)")
            throw error
        }
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
        do {
            // Check for cancellation before making the request
            try Task.checkCancellation()
            
            print("Starting to fetch transactions...")
            
            let response = try await client
                .from("transactions")
                .select()
                .execute()
            
            // Check for cancellation after getting response, before parsing
            try Task.checkCancellation()
            
            print("Successfully received transactions data")
            let data = response.data
            let transactions = try JSONDecoder().decode([TransactionResponse].self, from: data)
            print("Successfully decoded \(transactions.count) transactions")
            return transactions
        } catch let error as CancellationError {
            print("Transactions fetch was cancelled")
            throw error
        } catch {
            print("Error fetching transactions: \(error.localizedDescription)")
            throw error
        }
    }
    
    func addTransaction(assetId: String, type: TransactionType, quantity: Double, 
                         pricePerUnit: Double, totalAmount: Double, date: Date) async throws -> String {
        // Clear any previous errors
        clearError()
        
        let transactionData = TransactionInsert(
            asset_id: assetId,
            type: type.rawValue,
            quantity: quantity,
            price_per_unit: pricePerUnit,
            total_amount: totalAmount,
            transaction_date: date.toISO8601String()
        )
        
        print("Sending transaction to Supabase: \(transactionData)")
        
        let response = try await client
            .from("transactions")
            .insert(transactionData)
            .execute()
        
        print("Received response with status: \(response.status)")
        
        if response.status >= 200 && response.status < 300 {
            // Try to extract the ID of the newly created transaction
            if !response.data.isEmpty {
                do {
                    print("Response data: \(String(data: response.data, encoding: .utf8) ?? "Unable to convert to string")")
                    let transactions = try JSONDecoder().decode([TransactionResponse].self, from: response.data)
                    if let newTransaction = transactions.first {
                        print("Successfully decoded transaction with ID: \(newTransaction.id)")
                        return newTransaction.id
                    } else {
                        print("No transaction was returned in the response")
                    }
                } catch {
                    print("Error decoding transaction response: \(error)")
                    // Important: Don't set the error here as the transaction was successful
                    // We just couldn't decode the ID, but it doesn't mean the transaction failed
                }
            } else {
                print("Response data is empty, but status code indicates success")
                
                // Since we can't get the transaction ID, we'll need to query for it
                do {
                    // Small delay to allow the database to process the insertion
                    try await Task.sleep(nanoseconds: 500_000_000) // 0.5 second
                    
                    // Query for the most recent transaction with matching details
                    let fetchResponse = try await client
                        .from("transactions")
                        .select()
                        .eq("asset_id", value: assetId)
                        .eq("quantity", value: quantity)
                        .eq("price_per_unit", value: pricePerUnit)
                        .order("created_at", ascending: false)
                        .limit(1)
                        .execute()
                    
                    if let transactionData = try? JSONDecoder().decode([TransactionResponse].self, from: fetchResponse.data),
                       let transaction = transactionData.first {
                        print("Found matching transaction with ID: \(transaction.id)")
                        return transaction.id
                    }
                } catch {
                    print("Error fetching newly created transaction: \(error)")
                }
            }
            
            // If we still couldn't get the ID, generate a temporary one
            // This is a fallback to allow the UI to proceed normally
            let tempId = UUID().uuidString
            print("Using generated UUID as transaction ID: \(tempId)")
            return tempId
        } else {
            let error = NSError(
                domain: "SupabaseManager",
                code: response.status,
                userInfo: [NSLocalizedDescriptionKey: "Failed to add transaction: Status \(response.status)"]
            )
            setError(error)
            throw error
        }
    }
    
    func deleteTransaction(id: String) async throws -> Bool {
        // Clear any previous errors
        clearError()
        
        print("Deleting transaction with ID: \(id)")
        
        let response = try await client
            .from("transactions")
            .delete()
            .eq("id", value: id)
            .execute()
        
        print("Delete response status: \(response.status)")
        
        if response.status >= 200 && response.status < 300 {
            print("Successfully deleted transaction with ID: \(id)")
            return true
        } else {
            let error = NSError(
                domain: "SupabaseManager",
                code: response.status,
                userInfo: [NSLocalizedDescriptionKey: "Failed to delete transaction: Status \(response.status)"]
            )
            setError(error)
            throw error
        }
    }
    
    func deleteAsset(id: String) async throws -> Bool {
        // Clear any previous errors
        clearError()
        
        print("Deleting asset with ID: \(id)")
        
        // First, delete all transactions associated with this asset
        let transactionsResponse = try await client
            .from("transactions")
            .delete()
            .eq("asset_id", value: id)
            .execute()
        
        print("Delete transactions response status: \(transactionsResponse.status)")
        
        // Now delete the asset itself
        let assetResponse = try await client
            .from("assets")
            .delete()
            .eq("id", value: id)
            .execute()
        
        print("Delete asset response status: \(assetResponse.status)")
        
        if assetResponse.status >= 200 && assetResponse.status < 300 {
            print("Successfully deleted asset with ID: \(id)")
            return true
        } else {
            let error = NSError(
                domain: "SupabaseManager",
                code: assetResponse.status,
                userInfo: [NSLocalizedDescriptionKey: "Failed to delete asset: Status \(assetResponse.status)"]
            )
            setError(error)
            throw error
        }
    }
    
    // MARK: - Interest Rate History Functions
    func fetchInterestRateHistory() async throws -> [InterestRateHistoryResponse] {
        do {
            // Check for cancellation before making the request
            try Task.checkCancellation()
            
            print("Starting to fetch interest rate history...")
            
            let response = try await client
                .from("interest_rate_history")
                .select()
                .execute()
            
            // Check for cancellation after getting response, before parsing
            try Task.checkCancellation()
            
            print("Successfully received interest rate history data")
            let data = response.data
            let interestRates = try JSONDecoder().decode([InterestRateHistoryResponse].self, from: data)
            print("Successfully decoded \(interestRates.count) interest rates")
            return interestRates
        } catch let error as CancellationError {
            print("Interest rate history fetch was cancelled")
            throw error
        } catch {
            print("Error fetching interest rate history: \(error.localizedDescription)")
            throw error
        }
    }
    
    func getCurrentInterestRate(assetId: String) async throws -> Double? {
        do {
            // Check for cancellation before making the request
            try Task.checkCancellation()
            
            print("Starting to fetch current interest rate for asset \(assetId)...")
            
            let response = try await client
                .rpc("get_current_interest_rate", params: ["asset_uuid": assetId])
                .execute()
            
            // Check for cancellation after getting response
            try Task.checkCancellation()
            
            print("Successfully received current interest rate data")
            let data = response.data
            let rate = try JSONDecoder().decode(Double?.self, from: data)
            print("Successfully decoded current interest rate: \(String(describing: rate))")
            return rate
        } catch let error as CancellationError {
            print("Current interest rate fetch was cancelled")
            throw error
        } catch {
            print("Error getting current interest rate: \(error.localizedDescription)")
            throw error
        }
    }
    
    func addInterestRate(assetId: String, rate: Double, startDate: Date, endDate: Date? = nil) async throws -> String {
        let interestRateData = InterestRateInsert(
            asset_id: assetId,
            rate: rate,
            start_date: startDate.toISO8601String(),
            end_date: endDate != nil ? endDate!.toISO8601String() : nil
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

// MARK: - Date Utilities
extension Date {
    static func parseFromString(_ dateString: String) -> Date {
        // Try several date formats to ensure we parse correctly
        var parsedDate: Date?
        
        // 1. Try ISO8601 with fractional seconds
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        parsedDate = isoFormatter.date(from: dateString)
        
        // 2. Try ISO8601 without fractional seconds
        if parsedDate == nil {
            let simpleIsoFormatter = ISO8601DateFormatter()
            simpleIsoFormatter.formatOptions = [.withInternetDateTime]
            parsedDate = simpleIsoFormatter.date(from: dateString)
        }
        
        // 3. Try using DateFormatter for more flexibility
        if parsedDate == nil {
            let dateFormatter = DateFormatter()
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            
            // Try different formats
            let formats = [
                "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
                "yyyy-MM-dd'T'HH:mm:ssZ",
                "yyyy-MM-dd'T'HH:mm:ss",
                "yyyy-MM-dd"
            ]
            
            for format in formats {
                dateFormatter.dateFormat = format
                if let date = dateFormatter.date(from: dateString) {
                    parsedDate = date
                    break
                }
            }
        }
        
        // If we successfully parsed the date, use it, otherwise use current date
        return parsedDate ?? Date()
    }
    
    // Convert a date to ISO8601 string with fractional seconds
    func toISO8601String() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: self)
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
        return Asset(
            id: id,
            symbol: symbol,
            name: name,
            isin: isin,
            type: AssetType(rawValue: type) ?? .etf,
            created_at: Date.parseFromString(created_at),
            updated_at: Date.parseFromString(updated_at)
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
        return Transaction(
            id: id,
            asset_id: asset_id,
            type: TransactionType(rawValue: type) ?? .buy,
            quantity: quantity,
            price_per_unit: price_per_unit,
            total_amount: total_amount,
            transaction_date: Date.parseFromString(transaction_date),
            created_at: Date.parseFromString(created_at),
            updated_at: Date.parseFromString(updated_at)
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
        return InterestRateHistory(
            id: id,
            asset_id: asset_id,
            rate: rate,
            start_date: Date.parseFromString(start_date),
            end_date: end_date != nil ? Date.parseFromString(end_date!) : nil,
            created_at: Date.parseFromString(created_at),
            updated_at: Date.parseFromString(updated_at)
        )
    }
}
