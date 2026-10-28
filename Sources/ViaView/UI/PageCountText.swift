import AppKit

final class PageCountLabel: NSTextField {
    var fullCount = ""
    // NSTextField derives AXValue from its displayed string, ignoring setAccessibilityValue.
    override func accessibilityValue() -> String? { fullCount }
}

enum PageCountText {
    static func full(current: Int, total: Int) -> String {
        total > 0 ? "\(current) / \(total)" : "—"
    }

    static func candidates(current: Int, total: Int) -> [String] {
        let full = full(current: current, total: total)
        guard total >= 10_000 else { return [full] }
        let divisor = total >= 100_000_000 ? 100_000_000.0 : 10_000.0
        let unit = total >= 100_000_000 ? "亿" : "万"
        // Round totals upward so a near-final exact position never exceeds the displayed total.
        let value = ceil(Double(total) / divisor * 10) / 10
        let decimal = String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), value)
        let precise = decimal.hasSuffix(".0") ? String(decimal.dropLast(2)) : decimal
        let rounded = String(format: "%.0f", locale: Locale(identifier: "en_US_POSIX"), ceil(value))
        // Current position stays exact. Only the total is rounded, explicitly marked.
        return [full, "\(current) / 约\(precise)\(unit)", "\(current)/约\(precise)\(unit)",
                "\(current) / 约\(rounded)\(unit)", "\(current)/约\(rounded)\(unit)"]
    }
}

extension ViewerController {
    func updatePageCount(current: Int, total: Int) {
        for candidate in PageCountText.candidates(current: current, total: total) {
            countLabel.stringValue = candidate
            if countLabel.intrinsicContentSize.width <= ChromeMetrics.navigationTextWidth { break }
        }
        let full = PageCountText.full(current: current, total: total)
        countLabel.toolTip = full
        countLabel.setAccessibilityLabel("图片序号")
        countLabel.fullCount = full
    }
}
