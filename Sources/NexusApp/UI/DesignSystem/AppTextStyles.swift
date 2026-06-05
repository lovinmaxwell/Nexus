import SwiftUI

struct AppTextStyles {
    static let title = Font.system(size: 24, weight: .semibold, design: .rounded)
    static let headline = Font.system(size: 17, weight: .semibold, design: .rounded)
    static let body = Font.system(size: 14, weight: .regular, design: .rounded)
    static let caption = Font.system(size: 12, weight: .medium, design: .rounded)
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
