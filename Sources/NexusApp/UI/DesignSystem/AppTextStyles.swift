import SwiftUI

struct AppTextStyles {
    static let title = Font.system(size: 24, weight: .bold, design: .rounded)
    static let headline = Font.system(size: 18, weight: .semibold, design: .default)
    static let body = Font.system(size: 14, weight: .regular, design: .default)
    static let caption = Font.system(size: 12, weight: .medium, design: .default)
    static let mono = Font.system(size: 12, weight: .regular, design: .monospaced)
}

extension View {
    func appTitleStyle() -> some View {
        self.font(AppTextStyles.title).foregroundStyle(AppColors.textPrimary)
    }

    func appHeadlineStyle() -> some View {
        self.font(AppTextStyles.headline).foregroundStyle(AppColors.textPrimary)
    }

    func appBodyStyle() -> some View {
        self.font(AppTextStyles.body).foregroundStyle(AppColors.textSecondary)
    }

    func appCaptionStyle() -> some View {
        self.font(AppTextStyles.caption).foregroundStyle(AppColors.textSecondary)
    }
}
