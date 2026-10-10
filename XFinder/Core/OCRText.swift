import Foundation
import CoreGraphics

/// The pure half of "copy text from the screen": turning Vision's line observations into the text
/// that goes on the clipboard. Vision reports lines in its own bottom-left, normalised space and in
/// no guaranteed reading order, so the order and the noise rules live here, pinned by tests.
enum OCRText {

    struct Line: Equatable {
        var text: String
        /// Vision bounding box, normalised, origin bottom-left (so larger `maxY` = higher on screen).
        var box: CGRect
        var confidence: Float
    }

    /// Lines below this confidence are dropped: they are almost always icon edges and texture.
    static let minimumConfidence: Float = 0.3

    /// Reading order, top to bottom; lines that share a visual row (a table, a toolbar) join
    /// left-to-right with a tab so columns do not run together. nil when nothing usable was read —
    /// the caller must say "no text found", never put an empty string on the clipboard.
    static func assemble(_ lines: [Line]) -> String? {
        let usable = lines.filter {
            $0.confidence >= minimumConfidence && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !usable.isEmpty else { return nil }
        // Highest line first; a stable secondary key keeps equal rows deterministic.
        let sorted = usable.sorted { ($0.box.maxY, -$0.box.minX) > ($1.box.maxY, -$1.box.minX) }
        var rows: [[Line]] = []
        for line in sorted {
            if let last = rows.last?.first, sharesRow(last.box, line.box) {
                rows[rows.count - 1].append(line)
            } else {
                rows.append([line])
            }
        }
        let text = rows.map { row in
            row.sorted { $0.box.minX < $1.box.minX }
                .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
                .joined(separator: "\t")
        }.joined(separator: "\n")
        return text.isEmpty ? nil : text
    }

    /// Two boxes are on one row when their vertical overlap is more than half of the shorter one.
    static func sharesRow(_ a: CGRect, _ b: CGRect) -> Bool {
        let overlap = min(a.maxY, b.maxY) - max(a.minY, b.minY)
        let shorter = min(a.height, b.height)
        return shorter > 0 && overlap > shorter * 0.5
    }

    static func lineCount(_ text: String) -> Int { text.split(separator: "\n", omittingEmptySubsequences: true).count }
}
