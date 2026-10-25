import Foundation

/// XF-T30 W6 — the session's Problems list (FileOctopus): one row per failed operation with each failed item and a
/// canonical reason; Retry only for pre-write, plausibly transient failures. Pure, symlinked. W6 builder (pure).
enum ProblemReason: String, Codable, CaseIterable, Sendable {
    case permissionDenied, diskFull, fileInUse, disconnected, readWriteError, timeout, readOnlyVolume, nameTooLong, itemGone, other

    /// L10n key (spec R51's canonical vocabulary — the Vietnamese source sentence itself, per repo convention).
    var titleKey: String {
        switch self {
        case .permissionDenied: return "Không có quyền"
        case .diskFull: return "Ổ đĩa đầy"
        case .fileInUse: return "Tệp đang được dùng"
        case .disconnected: return "Ổ đĩa hoặc máy chủ mất kết nối"
        case .readWriteError: return "Lỗi đọc hoặc ghi"
        case .timeout: return "Hết giờ"
        case .readOnlyVolume: return "Ổ đĩa chỉ đọc"
        case .nameTooLong: return "Tên quá dài"
        case .itemGone: return "Mục không còn tồn tại"
        case .other: return ""
        }
    }

    /// Maps the POSIX codes a file operation can actually surface (via `errno`, or a `CocoaError.Code.fileWriteXxx`
    /// carrying one in `userInfo[NSUnderlyingErrorKey]`) to the canonical vocabulary in spec R51. Anything outside
    /// this set falls back to `.other`, which is shown with the raw system message instead of a canonical title.
    static func from(posix code: Int32) -> ProblemReason {
        switch code {
        case EACCES, EPERM: return .permissionDenied
        case ENOSPC, EDQUOT: return .diskFull
        case EBUSY, ETXTBSY: return .fileInUse
        case ENOTCONN, ESHUTDOWN, EHOSTDOWN, EHOSTUNREACH, ECONNRESET, ECONNABORTED: return .disconnected
        case EIO: return .readWriteError
        case ETIMEDOUT: return .timeout
        case EROFS: return .readOnlyVolume
        case ENAMETOOLONG: return .nameTooLong
        case ENOENT: return .itemGone
        default: return .other
        }
    }
}

struct ProblemItem: Equatable, Sendable {
    var path: String
    var reason: ProblemReason
    var systemMessage: String?
    var beforeWrite: Bool
}

struct ProblemEntry: Equatable, Identifiable, Sendable {
    var id: UUID
    var operationTitleKey: String
    var finished: Date
    var items: [ProblemItem]

    /// Retry is only offered when EVERY item in the row is a pre-write, plausibly-transient failure (spec R48) —
    /// one item that already wrote something (mid-copy I/O error, say) makes the whole row's retry unsafe, since
    /// retrying would re-run the plausibly-already-partial items too. An empty row has nothing to retry.
    var canRetry: Bool {
        !items.isEmpty && items.allSatisfy { $0.beforeWrite && $0.reason.isRetryable }
    }
}

private extension ProblemReason {
    /// Spec R48: retry is for permission/space/read-write/timeout-class causes — conditions that can plausibly
    /// clear up on their own (free space appears, a lock releases, a flaky link recovers). `.itemGone` and
    /// `.nameTooLong` are not transient (the condition that caused them does not spontaneously change), and
    /// `.other` is an unclassified system error with no promise of being retry-safe.
    var isRetryable: Bool {
        switch self {
        case .permissionDenied, .diskFull, .fileInUse, .disconnected, .readWriteError, .timeout, .readOnlyVolume:
            return true
        case .nameTooLong, .itemGone, .other:
            return false
        }
    }
}

struct ProblemsList: Equatable, Sendable {
    private(set) var entries: [ProblemEntry] = []

    /// New entries land at the front: the row for the operation that JUST finished is what the user wants to see
    /// first, matching the alert-then-reveal flow in spec §8 (the alert interrupts the user right after the
    /// failure, so the matching row should be the first thing in the list they land on).
    mutating func add(_ entry: ProblemEntry) {
        entries.insert(entry, at: 0)
    }

    mutating func dismiss(_ id: UUID) {
        entries.removeAll { $0.id == id }
    }

    mutating func clearAll() { entries = [] }
}
