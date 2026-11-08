import Foundation

/// Where a half-finished extraction is kept so the user can still get at it.
///
/// The rule this exists for (spec §7): a batch that placed three of five items must not delete the
/// other two and must not claim "nothing changed". The staged remainder moves here instead of being
/// removed, and the page prints where it went. Nothing in this store is ever deleted automatically —
/// not on launch, not on cancel (spec §7: no automatic destructive replay), only when the user asks
/// through the page.
///
/// Deliberately a plain directory, not DatabaseService: recovery data must survive a schema
/// migration it knows nothing about, and it is not user data.
enum ArchiveRecoveryStore {

    /// App-owned root, one level under the user's Application Support. 0700: a recovered staging
    /// folder holds the archive's payload, which is exactly as private as the archive itself.
    static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("XFinder").appendingPathComponent("ArchiveRecovery")
    }

    /// Batches currently waiting for the user, newest first. A folder is only listed when it is a real
    /// directory inside the root — never a symlink, never something outside it.
    static func pending() -> [URL] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: root.path) else { return [] }
        var found: [(URL, Date)] = []
        for name in names where name.hasPrefix("batch-") {
            let url = root.appendingPathComponent(name)
            var info = stat()
            guard lstat(url.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR else { continue }
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            found.append((url, date))
        }
        return found.sorted { $0.1 > $1.1 }.map(\.0)
    }

    /// How many items a recovered batch still holds, for the page's one-line summary.
    static func itemCount(in batch: URL) -> Int {
        (try? FileManager.default.contentsOfDirectory(atPath: batch.path))?.count ?? 0
    }

    /// Move one recovered batch to the Trash, **at the user's explicit request only**. Trash, never `removeItem`
    /// (CLAUDE.md rule 9): a recovered batch is the archive's payload, i.e. the user's data. Returning the error rather
    /// than swallowing it is what lets the page say which batch could not be removed. `trash` is injected so a test
    /// never touches the real Trash.
    static func remove(_ batch: URL,
                       trash: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) throws {
        let rootPath = root.standardizedFileURL.path
        let targetPath = batch.standardizedFileURL.path
        guard targetPath.hasPrefix(rootPath + "/") else {
            throw Failure.outsideRoot(targetPath)
        }
        try trash(batch)
    }

    enum Failure: Error, CustomStringConvertible {
        case outsideRoot(String)

        var description: String {
            switch self {
            case .outsideRoot(let path): return "refusing to delete outside the recovery root: \(path)"
            }
        }
    }
}
