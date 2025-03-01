import Foundation

// MARK: - Price Data
struct PriceData: Codable {
    var price: Double
    var change24h: Double?
    var dayHigh: Double?
    var dayLow: Double?
    var previousClose: Double?
    var volume: Double?
    
    // Create an empty price data instance
    static func empty() -> PriceData {
        return PriceData(price: 0.0)
    }
} 