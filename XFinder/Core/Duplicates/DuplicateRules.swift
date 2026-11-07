import Foundation

struct DuplicateFingerprint: Sendable, Equatable, Hashable {
    let device: UInt64
    let inode: UInt64
    let size: Int64
    let modifiedSeconds: Int64
    let modifiedNanos: Int64
    let changedSeconds: Int64
    let changedNanos: Int64
    var identity: String { "\(device):\(inode)" }
}

struct DuplicateFile: Sendable, Equatable, Identifiable {
    let url: URL
    let relativePath: String
    let fingerprint: DuplicateFingerprint
    var id: String { url.path }
    var name: String { url.lastPathComponent }
}

struct DuplicateGroup: Sendable, Equatable, Identifiable {
    let files: [DuplicateFile]
    var id: String { files.first?.id ?? "" }
}

enum DuplicateScanStatus: Sendable { case complete, incomplete, cancelled, failed }
struct DuplicateResult: Sendable {
    let groups: [DuplicateGroup]
    let status: DuplicateScanStatus
    let scanned: Int
    let skipped: Int
}
struct DuplicateProgress: Sendable {
    enum Phase: Sendable { case grouping, hashing, comparing, verifying, moving }
    let phase: Phase
    let processed: Int
    let skipped: Int
}
struct DuplicateMove: Sendable {
    let file: DuplicateFile
    let keeper: DuplicateFile
}

/// No filesystem effects: these rules gate all destructive operations.
enum DuplicateRules {
    static let workers = 4
    static let fileLimit = 500_000
    static let chunkSize = 1_048_576

    static func keeperFirst(_ a: DuplicateFile, _ b: DuplicateFile) -> Bool {
        let ad = a.relativePath.split(separator: "/").count
        let bd = b.relativePath.split(separator: "/").count
        if ad != bd { return ad < bd }
        if a.fingerprint.modifiedSeconds != b.fingerprint.modifiedSeconds {
            return a.fingerprint.modifiedSeconds < b.fingerprint.modifiedSeconds
        }
        if a.fingerprint.modifiedNanos != b.fingerprint.modifiedNanos {
            return a.fingerprint.modifiedNanos < b.fingerprint.modifiedNanos
        }
        return a.relativePath.utf8.lexicographicallyPrecedes(b.relativePath.utf8)
    }

    static func sizeCandidates(_ files: [DuplicateFile]) -> [[DuplicateFile]] {
        var seen = Set<String>()
        var sizes: [Int64: [DuplicateFile]] = [:]
        for file in files.sorted(by: keeperFirst) where seen.insert(file.fingerprint.identity).inserted {
            sizes[file.fingerprint.size, default: []].append(file)
        }
        return sizes.keys.sorted().compactMap { sizes[$0] }.filter { $0.count > 1 }
    }

    static func plan(groups: [DuplicateGroup], selected: Set<String>, complete: Bool) -> [DuplicateMove]? {
        guard complete, !selected.isEmpty else { return nil }
        var covered = Set<String>()
        var moves: [DuplicateMove] = []
        for group in groups {
            let chosen = group.files.filter { selected.contains($0.id) }
            guard !chosen.isEmpty else { continue }
            covered.formUnion(chosen.map(\.id))
            guard let keeper = group.files.first(where: { !selected.contains($0.id) }) else { return nil }
            for file in chosen {
                guard file.fingerprint.identity != keeper.fingerprint.identity else { return nil }
                moves.append(.init(file: file, keeper: keeper))
            }
        }
        guard covered == selected else { return nil }
        return moves.isEmpty ? nil : moves
    }

    static func fingerprintsMatch(_ a: DuplicateFingerprint, _ b: DuplicateFingerprint) -> Bool { a == b }

    static func mayMove(selected: Bool, cancelled: Bool, fingerprintsMatch: Bool, hasKeeper: Bool) -> Bool {
        selected && !cancelled && fingerprintsMatch && hasKeeper
    }
}
