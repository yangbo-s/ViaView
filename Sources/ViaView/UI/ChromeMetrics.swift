import AppKit

enum ChromeMetrics {
    static let iconSize: CGFloat = 20
    static let buttonSize: CGFloat = 32
    static let inset: CGFloat = 4
    static let spacing: CGFloat = 4
    static let edgeInset: CGFloat = 12
    static let height = buttonSize + inset * 2
    static let radius = height / 2
    static let maximumNavigationWidth: CGFloat = 200
    static let navigationTextWidth = maximumNavigationWidth - buttonSize * 2 - spacing * 2 - inset * 2
}
