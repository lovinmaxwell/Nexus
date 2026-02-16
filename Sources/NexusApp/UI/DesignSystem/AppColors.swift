import SwiftUI

struct AppColors {
    // MARK: - Core Palette
    // Using hardcoded values as fallback since Asset Catalog might be missing these sets
    static let background = Color(hex: "0F0F0F")  // Deep dark background
    static let surface = Color(hex: "1C1C1E").opacity(0.6)  // Glass-like surface
    static let accent = Color(hex: "0A84FF")  // iOS Blue-like accent (Neon Blue)
    static let textPrimary = Color.white
    static let textSecondary = Color.gray

    // MARK: - Functional Colors
    static let success = Color(hex: "30D158")  // Green
    static let warning = Color(hex: "FF9F0A")  // Orange
    static let error = Color(hex: "FF453A")  // Red
    static let info = Color(hex: "64D2FF")  // Light Blue

    // MARK: - Gradients
    static let primaryGradient = LinearGradient(
        colors: [Color(hex: "4A90E2"), Color(hex: "0056D2")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let glassGradient = LinearGradient(
        colors: [.white.opacity(0.1), .white.opacity(0.05)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a: UInt64
        let r: UInt64
        let g: UInt64
        let b: UInt64
        switch hex.count {
        case 3:  // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:  // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:  // ARGB (32-bit)
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
