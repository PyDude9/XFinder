import Foundation
import AppKit

/// Tính toán biểu thức số học đơn giản
final class Calculator {
    static let shared = Calculator()

    private init() {}

    func evaluate(query: String) -> CommandResult? {
        // Chỉ xử lý nếu query có số và toán tử
        let mathPattern = #"^[\d\s\+\-\*\/\.\(\)]+$"#
        guard query.range(of: mathPattern, options: .regularExpression) != nil else {
            return nil
        }

        // Dùng NSExpression để tính toán an toàn
        let expr = NSExpression(format: query)
        guard let result = expr.expressionValue(with: nil, context: nil) as? NSNumber else {
            return nil
        }

        let resultValue = result.doubleValue
        let formatted = formatNumber(resultValue)

        return CommandResult(
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
