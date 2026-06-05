import AppKit
import SwiftUI

struct AppColors {
    // MARK: - Core Palette
    static let background = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor).opacity(0.72)
    static let accent = Color.accentColor
    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary

    // MARK: - Functional Colors
    static let success = Color(nsColor: .systemGreen)
    static let warning = Color(nsColor: .systemOrange)
    static let error = Color(nsColor: .systemRed)
    static let info = Color(nsColor: .systemTeal)

    // MARK: - Gradients
    static let primaryGradient = LinearGradient(
        colors: [accent.opacity(0.9), accent.opacity(0.45)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let glassGradient = LinearGradient(
        colors: [.white.opacity(0.22), .white.opacity(0.05)],
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
