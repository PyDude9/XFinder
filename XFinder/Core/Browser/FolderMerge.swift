import Foundation

/// XF-T30 W6 — merging one folder into another (FileOctopus "Merge…"). Pure planning over two trees, symlinked into
/// the test package. Contract XF-T30-w6 §1. W6 builder (pure): implement.
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
    var willCopy: Int { 0 }
    var willReplace: Int { 0 }
    var willSkip: Int { 0 }
    var willRename: Int { 0 }
}

enum FolderMerge {
    enum Refusal: Equatable, Sendable { case nested, sameFolder }
    /// FAT volumes keep 2-second timestamps.
    static func newerThreshold(fat: Bool) -> TimeInterval { fat ? 2 : 1 }
    static func plan(source: [MergeNode], destination: [MergeNode], policy: MergePolicy, fat: Bool) -> MergePlan { MergePlan(steps: []) }
    static func refusal(source: String, destination: String) -> Refusal? { nil }
}
