import Foundation

/// NUL-separated output (`mdfind -0`) read chunk by chunk, keeping at most `limit` records (symlinked into the test
/// package). The reader can stop the child as soon as `isFull`, instead of reading everything and keeping 100.
///
/// Measured 2026-10-23 on this Mac: "ảnh" (`public.image`) = 51 615 paths, 7.2 MB, 2.0 s; the broadest query
/// (`public.item`) = 1 122 239 paths, **134 MB, 35 s** — all read into one String to show 50 rows.
struct NulRecords {
    let limit: Int
    private(set) var records: [String] = []
    /// There was at least one record beyond `limit` (the page says "100+", not "100").
    private(set) var truncated = false
    private var partial = Data()

    init(limit: Int) { self.limit = max(0, limit) }

    var isFull: Bool { records.count >= limit }

    /// Feed the next chunk. Once full, any further byte only marks the output as truncated.
    mutating func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        if isFull { truncated = true; return }
        var rest = chunk[...]
        while let nul = rest.firstIndex(of: 0) {
            let piece = partial + rest[rest.startIndex..<nul]
            partial.removeAll(keepingCapacity: true)
            rest = rest[rest.index(after: nul)...]
            guard !piece.isEmpty else { continue }
            if isFull { truncated = true; return }
            records.append(String(decoding: piece, as: UTF8.self))
        }
        if !rest.isEmpty {
            if isFull { truncated = true } else { partial.append(contentsOf: rest) }
        }
    }

    /// End of output: a last record without its NUL still counts.
    mutating func finish() {
        guard !partial.isEmpty else { return }
        if isFull { truncated = true } else { records.append(String(decoding: partial, as: UTF8.self)) }
        partial.removeAll()
    }
}
