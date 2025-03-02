import Foundation

/// Manages access to application configuration values
struct ConfigurationManager {
    // MARK: - Singleton
    
    /// Shared instance of the configuration manager
    static let shared = ConfigurationManager()
    
    // MARK: - Constants
    
    private let placeholderText = "YOUR_"
    
    // MARK: - Properties
    
    private let configurationDictionary: [String: Any]
    
    // MARK: - Initialization
    
    private init() {
        // Load configuration from ApiKeys.plist
        guard let path = Bundle.main.path(forResource: "ApiKeys", ofType: "plist"),
              let dictionary = NSDictionary(contentsOfFile: path) as? [String: Any] else {
            print("WARNING: ApiKeys.plist not found or is invalid. Using fallback values.")
            self.configurationDictionary = [:]
            return
        }
        
        self.configurationDictionary = dictionary
    }
    
    // MARK: - API
    
    /// Get the Supabase URL
    var supabaseURL: String {
        return string(for: "SUPABASE_URL") ?? ""
    }
    
    /// Get the Supabase API key
    var supabaseKey: String {
        return string(for: "SUPABASE_KEY") ?? ""
    }
    
    /// Get the RapidAPI key
    var rapidAPIKey: String {
        return string(for: "RAPIDAPI_KEY") ?? ""
    }
    
    // MARK: - Validation Methods
    
    /// Check if Supabase credentials are valid (not empty and not placeholders)
    var hasValidSupabaseCredentials: Bool {
        return isValidAPIKey(supabaseURL) && isValidAPIKey(supabaseKey)
    }
    
    /// Check if RapidAPI key is valid (not empty and not a placeholder)
    var hasValidRapidAPIKey: Bool {
        return isValidAPIKey(rapidAPIKey)
    }
    
    /// Check if a key is valid (not empty and not a placeholder)
    func isValidAPIKey(_ key: String) -> Bool {
        return !key.isEmpty && !key.contains(placeholderText)
    }
    
    // MARK: - Helper Methods
    
    /// Get a string value from the configuration
    private func string(for key: String) -> String? {
        return configurationDictionary[key] as? String
    }
    
    /// Get a boolean value from the configuration
    private func bool(for key: String) -> Bool? {
        return configurationDictionary[key] as? Bool
    }
    
    /// Get an integer value from the configuration
    private func integer(for key: String) -> Int? {
        return configurationDictionary[key] as? Int
    }
    
    /// Get a double value from the configuration
    private func double(for key: String) -> Double? {
        return configurationDictionary[key] as? Double
    }
} 