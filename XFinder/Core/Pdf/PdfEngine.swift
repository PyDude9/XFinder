import Foundation

/// Pure rules for the PDF tools (page, Notch hub): page-range parsing and output naming.
///
/// Measured by the B2 survey before this existed: `PDFDocument.write(to:)` silently overwrites an
/// existing file, and the page wrote to deterministic names (`<stem>-pages.pdf`, `<stem>-rotated.pdf`)
/// and to `Merged-<seconds>.pdf` — so running a tool twice (or two merges in one second) replaced
/// the previous result without a word. Every output name now goes through the keep-both rule.
enum PdfEngine {

    enum Tool: String, CaseIterable { case merge, extract, rotate, reorder }

    /// "1-3", "2,5,7", "1-2, 4" → sorted, de-duplicated, 0-based indices. 1-based input as the user
    /// sees pages. Empty text means "all pages" only when `emptyMeansAll` (rotate), else invalid
    /// (extract would produce a copy of the whole file). Any malformed or out-of-range part ⇒ nil.
    static func pageIndices(_ text: String, pageCount: Int, emptyMeansAll: Bool) -> [Int]? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard pageCount > 0 else { return nil }
        if t.isEmpty { return emptyMeansAll ? Array(0..<pageCount) : nil }
        var pages = Set<Int>()
        for part in t.split(separator: ",", omittingEmptySubsequences: false) {
            let p = part.trimmingCharacters(in: .whitespaces)
            if p.isEmpty { return nil }
            if p.contains("-") {
                let ends = p.split(separator: "-", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
                guard ends.count == 2, let a = Int(ends[0]), let b = Int(ends[1]),
                      a >= 1, b <= pageCount, a <= b else { return nil }
                pages.formUnion(a...b)
            } else {
                guard let n = Int(p), n >= 1, n <= pageCount else { return nil }
                pages.insert(n)
            }
        }
        return pages.sorted().map { $0 - 1 }
    }

    /// Full-document ordering. Unlike extraction ranges this preserves the requested sequence and
    /// rejects omissions/duplicates, so a typo cannot silently delete a page.
    static func orderedPageIndices(_ text: String, pageCount: Int) -> [Int]? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard pageCount > 0, !t.isEmpty else { return nil }
        var ordered: [Int] = []
        for part in t.split(separator: ",", omittingEmptySubsequences: false) {
            let component = part.trimmingCharacters(in: .whitespaces)
            guard !component.isEmpty else { return nil }
            if component.contains("-") {
                let ends = component.split(separator: "-", omittingEmptySubsequences: false)
                guard ends.count == 2, let first = Int(ends[0].trimmingCharacters(in: .whitespaces)),
                      let last = Int(ends[1].trimmingCharacters(in: .whitespaces)),
                      first >= 1, last <= pageCount, first <= last else { return nil }
                ordered.append(contentsOf: first...last)
            } else {
                guard let page = Int(component), (1...pageCount).contains(page) else { return nil }
                ordered.append(page)
            }
        }
        guard ordered.count == pageCount, Set(ordered).count == pageCount else { return nil }
        return ordered.map { $0 - 1 }
    }

    /// Base name of a tool's output, before the keep-both numbering.
    static func outputName(tool: Tool, sourceStem: String) -> String {
        switch tool {
        case .merge: return "Merged.pdf"
        case .extract: return "\(sourceStem)-pages.pdf"
        case .rotate: return "\(sourceStem)-rotated.pdf"
        case .reorder: return "\(sourceStem)-ordered.pdf"
        }
    }

    /// Where the output goes: never onto an existing file ("X.pdf" → "X 2.pdf"…), never onto a source.
    static func outputURL(tool: Tool, sources: [URL], folder: URL, exists: (URL) -> Bool) -> URL {
        let stem = sources.first.map { $0.deletingPathExtension().lastPathComponent } ?? "Document"
        let base = folder.appendingPathComponent(outputName(tool: tool, sourceStem: stem))
        let sourcePaths = Set(sources.map { $0.standardizedFileURL.path })
        let taken: (URL) -> Bool = { exists($0) || sourcePaths.contains($0.standardizedFileURL.path) }
        guard case .write(let url) = ArchiveEngine.destination(base: base, policy: .keepBoth, exists: taken) else { return base }
        return url
    }
}
