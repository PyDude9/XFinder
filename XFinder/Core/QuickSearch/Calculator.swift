import Foundation
import AppKit

/// Tính toán biểu thức số học đơn giản
/// `Sendable`: không có trạng thái dùng chung, chỉ dùng an toàn từ mọi luồng.
final class Calculator: Sendable {
    static let shared = Calculator()

    private init() {}

    func evaluate(query: String) -> QuickSearchResult? {
        // Chỉ xử lý khi có cả số VÀ toán tử — "123" đơn thuần là người ta
        // đang tìm tên file chứ không phải tính toán.
        let mathPattern = #"^[\d\s\+\-\*\/\.\(\)]+$"#
        let hasDigit = query.contains(where: \.isNumber)
        let hasOperator = query.contains { "+-*/".contains($0) }
        guard query.range(of: mathPattern, options: .regularExpression) != nil,
              hasDigit, hasOperator else {
            return nil
        }

        // Never NSExpression(format:): it raises an Objective-C exception on malformed input ("1+", "(1+2"),
        // which Swift cannot catch — the whole app aborted mid-typing. SafeArithmetic returns nil instead,
        // and refuses division by zero rather than answering 0.
        guard let resultValue = SafeArithmetic.evaluate(query) else { return nil }
        let formatted = formatNumber(resultValue)

        return QuickSearchResult(
            type: .calculator,
            title: "= \(formatted)",
            subtitle: query,
            icon: NSImage(systemSymbolName: "equal.circle.fill", accessibilityDescription: nil),
            action: {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(formatted, forType: .string)
            }
        )
    }

    private func formatNumber(_ value: Double) -> String {
        // Nếu là số nguyên, không hiện .0
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", value)
        } else {
            // Làm tròn đến 6 chữ số thập phân
            let rounded = (value * 1_000_000).rounded() / 1_000_000
            return String(rounded)
        }
    }
}
