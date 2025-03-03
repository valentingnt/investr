import SwiftUI

/// Theme defines the visual styling for the entire app
struct Theme {
    // MARK: - Colors
    struct Colors {
        // Primary UI colors
        static let background = Color(UIColor { traitCollection in
            return traitCollection.userInterfaceStyle == .dark ? UIColor(hex: "2b2b2b") : UIColor(hex: "fffdf9")
        })
        static let secondaryBackground = Color(UIColor { traitCollection in
            return traitCollection.userInterfaceStyle == .dark ? UIColor(hex: "353535") : UIColor(hex: "f5f3ef")
        })
        static let accent = Color(hex: "7ca2c5") // RGB : 124 162 197
        
        // Text colors
        static let primaryText = Color(UIColor { traitCollection in
            return traitCollection.userInterfaceStyle == .dark ? UIColor(hex: "fffdf9") : UIColor(hex: "2b2b2b")
        })
        static let secondaryText = Color(UIColor { traitCollection in
            return traitCollection.userInterfaceStyle == .dark ? UIColor(hex: "cccccc") : UIColor(hex: "666666")
        })
        
        // Semantic colors
        static let positive = Color(hex: "4BB543") // Green for profits
        static let negative = Color(hex: "FF3B30") // Red for losses
        
        // Separator
        static let separator = Color(UIColor { traitCollection in
            return traitCollection.userInterfaceStyle == .dark ? UIColor(hex: "444444") : UIColor(hex: "e0ded9")
        })
    }
    
    // MARK: - Typography
    struct Typography {
        // Title
        static let largeTitle = Font.system(size: 34, weight: .bold, design: .default)
        static let title = Font.system(size: 28, weight: .bold, design: .default)
        static let title2 = Font.system(size: 22, weight: .bold, design: .default)
        static let title3 = Font.system(size: 20, weight: .bold, design: .default)
        
        // Body
        static let body = Font.system(size: 17, weight: .regular, design: .default)
        static let bodyBold = Font.system(size: 17, weight: .semibold, design: .default)
        
        // Caption
        static let caption = Font.system(size: 14, weight: .regular, design: .default)
        static let captionBold = Font.system(size: 14, weight: .semibold, design: .default)
        
        // Price displays
        static let price = Font.system(size: 24, weight: .semibold, design: .monospaced)
        static let largePrice = Font.system(size: 40, weight: .bold, design: .monospaced)
    }
    
    // MARK: - Layout
    struct Layout {
        static let cornerRadius: CGFloat = 12
        static let padding: CGFloat = 16
        static let cardPadding: CGFloat = 20
        static let smallPadding: CGFloat = 8
        static let spacing: CGFloat = 16
        static let smallSpacing: CGFloat = 8
    }
}

// MARK: - Helper Extensions
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// Add a UIColor extension to support hex colors for UIKit as well
extension UIColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: CGFloat(a) / 255
        )
    }
}

// MARK: - Modifiers
extension View {
    // Card styling
    func cardStyle() -> some View {
        self
            .padding(Theme.Layout.cardPadding)
            .background(Theme.Colors.secondaryBackground)
            .cornerRadius(Theme.Layout.cornerRadius)
    }
    
    // Tag/pill styling
    func tagStyle() -> some View {
        self
            .padding(.horizontal, Theme.Layout.smallPadding)
            .padding(.vertical, 4)
            .background(Theme.Colors.accent.opacity(0.2))
            .cornerRadius(6)
    }
} 