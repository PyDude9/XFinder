import Foundation

/// XF-T30 W6 — merging one folder into another (FileOctopus "Merge…"). Pure planning over two trees, symlinked into
/// the test package. Contract XF-T30-w6 §1. W6 builder (pure): implement.
///
/// `source`/`destination` are flat listings of a tree (every file and directory, `relativePath` relative to the
/// merge root) rather than a nested structure — flat lists are what a directory walk naturally produces and they
/// make "does this path have a counterpart on the other side" a dictionary lookup instead of a tree walk.
enum MergePolicy: String, Codable, CaseIterable, Sendable { case keepBoth, skip, keepNewer }

struct MergeNode: Equatable, Sendable {
    var relativePath: String
    var isDirectory: Bool
    var isPackage: Bool
    var isSymlink: Bool
    var size: Int64
    var modified: Date
    var isCloudFolder: Bool
}

struct MergePlan: Equatable, Sendable {
    enum Step: Equatable, Sendable {
        case copy(String), replace(String), skip(String), keepBoth(from: String, to: String), excluded(String, reason: String)
    }
    var steps: [Step]

    var willCopy: Int { steps.reduce(0) { $1.isCopy ? $0 + 1 : $0 } }
    var willReplace: Int { steps.reduce(0) { if case .replace = $1 { return $0 + 1 }; return $0 } }
    var willSkip: Int { steps.reduce(0) { if case .skip = $1 { return $0 + 1 }; return $0 } }
    var willRename: Int { steps.reduce(0) { if case .keepBoth = $1 { return $0 + 1 }; return $0 } }
}

private extension MergePlan.Step {
    /// `copy` counts new items; `keepBoth` also lands as a copy (under a renamed path) for the preview tally — spec
    /// §6 "new items" vs. "name-colliding items" is a distinction of WHY something copies, not whether it does.
    var isCopy: Bool {
        switch self {
        case .copy: return true
        default: return false
        }
    }
}

enum FolderMerge {
    enum Refusal: Equatable, Sendable { case nested, sameFolder }

    /// FAT/exFAT volumes only store 2-second timestamp resolution (spec R25); APFS/HFS+ use the ordinary 1-second
    /// Finder convention.
    static func newerThreshold(fat: Bool) -> TimeInterval { fat ? 2 : 1 }

    /// Merge is refused outright (R28) when either side is nested inside the other, including the degenerate case
    /// of merging a folder into itself. Checked by `FileOperationRules.isInside`/path equality so the same
    /// normalization (standardized path components, not string prefix) governs every nesting check in the browser.
    static func refusal(source: String, destination: String) -> Refusal? {
        let sourceStandard = (source as NSString).standardizingPath
        let destinationStandard = (destination as NSString).standardizingPath
        if sourceStandard == destinationStandard { return .sameFolder }
        if FileOperationRules.isInside(destinationStandard, ancestor: sourceStandard) { return .nested }
        if FileOperationRules.isInside(sourceStandard, ancestor: destinationStandard) { return .nested }
        return nil
    }

    /// Builds the merge plan: one `Step` per source item, deciding copy / replace / skip / keep-both / excluded.
    /// Items that exist ONLY at the destination are never touched — merge only ever adds/overwrites, it does not
    /// delete things the destination already had and the source never mentioned.
    static func plan(source: [MergeNode], destination: [MergeNode], policy: MergePolicy, fat: Bool) -> MergePlan {
        let destinationByPath = Dictionary(uniqueKeysWithValues: destination.map { ($0.relativePath, $0) })
        var destinationPaths = Set(destination.map(\.relativePath))
        var steps: [MergePlan.Step] = []

        for node in source {
            guard let existing = destinationByPath[node.relativePath] else {
                // No collision: a brand-new item copies straight across, UNLESS it sits inside an excluded folder
                // already reported at the ancestor level (handled by `isInsideExcludedAncestor` below) — walking
                // source order top-down and recording excluded directory paths as we go keeps that O(depth), not
                // O(n^2), without needing a second pass.
                if isInsideExcludedAncestor(node.relativePath, steps: steps) {
                    continue
                }
                steps.append(.copy(node.relativePath))
                destinationPaths.insert(node.relativePath)
                continue
            }

            // Packages, symlinks, cloud folders, and type mismatches are excluded as whole atomic units (R27):
            // never recursed into, never replaced — kept-both or skipped like any other top-level conflict, so a
            // caller still gets a disposition for them instead of silent omission.
            if let reason = exclusionReason(node, existing) {
                switch policy {
                case .skip:
                    steps.append(.skip(node.relativePath))
                case .keepBoth, .keepNewer:
                    steps.append(.excluded(node.relativePath, reason: reason))
                }
                continue
            }

            if isInsideExcludedAncestor(node.relativePath, steps: steps) {
                continue
            }

            // Two directories by the same name are not a conflict in themselves — the children underneath are what
            // collide or not, each on their own step. A directory-vs-directory pair with no colliding descendant at
            // all would otherwise never appear in the plan; that is fine, there is nothing to copy or skip for it.
            if node.isDirectory, existing.isDirectory {
                continue
            }

            switch policy {
            case .skip:
                steps.append(.skip(node.relativePath))
            case .keepBoth:
                let renamed = FileOperationRules.keepBothName(for: node.relativePath, existing: destinationPaths)
                steps.append(.keepBoth(from: node.relativePath, to: renamed))
                destinationPaths.insert(renamed)
            case .keepNewer:
                if FileOperationRules.isNewer(node.modified, than: existing.modified, coarseTimestamps: fat) {
                    steps.append(.replace(node.relativePath))
                } else {
                    steps.append(.skip(node.relativePath))
                }
            }
        }
        return MergePlan(steps: steps)
    }

    /// A plain file colliding with a plain file is never excluded — only packages/symlinks/cloud folders, or a
    /// type mismatch (file vs. folder either way), are. Returns an L10n key naming the reason, or nil for an
    /// ordinary file/file or folder/folder pair.
    private static func exclusionReason(_ source: MergeNode, _ destination: MergeNode) -> String? {
        if source.isPackage || destination.isPackage { return "Gói ứng dụng — không gộp bên trong" }
        if source.isSymlink || destination.isSymlink { return "Liên kết tượng trưng — không gộp bên trong" }
        if source.isCloudFolder || destination.isCloudFolder { return "Thư mục đám mây — không gộp bên trong" }
        if source.isDirectory != destination.isDirectory { return "Khác kiểu mục — tệp và thư mục cùng tên" }
        return nil
    }

    /// `relativePath` is a descendant of a directory that was just excluded as a whole unit (package/symlink/cloud/
    /// type-mismatch) earlier in this same pass — its children must not get their own independent steps.
    private static func isInsideExcludedAncestor(_ relativePath: String, steps: [MergePlan.Step]) -> Bool {
        for step in steps {
            guard case .excluded(let excludedPath, _) = step else { continue }
            if FileOperationRules.isInside(relativePath, ancestor: excludedPath) { return true }
        }
        return false
    }
}
