import Foundation

/// Pure Drop Tray rules (XF-T41 + Phase 1): file availability/error states, multi-selection reducer,
/// drag-out filtering, and post-move reconciliation so failed/skipped/cancelled moves never drop
/// items from the tray. Foundation-only so `Tests/XFinderLogicTests` verifies every case directly.
enum DropTrayItemStatus: Equatable, Sendable, Codable {
    case ready
    case movedOrMissing
    case permissionDenied
    case transferFailed(String)

    /// Ready items and previously failed transfers remain actionable (the user can retry or inspect);
    /// moved/missing or unreadable files cannot be copied/moved/dragged out until fixed.
    var isActionable: Bool {
        switch self {
        case .ready, .transferFailed: return true
        case .movedOrMissing, .permissionDenied: return false
        }
    }

    var isUnavailable: Bool { !isActionable }

    /// Localized store key explaining the non-ready state (`nil` when `.ready`).
    var statusKey: String? {
        switch self {
        case .ready: return nil
        case .movedOrMissing: return "Đã di chuyển hoặc bị xoá"
        case .permissionDenied: return "Không có quyền đọc tệp"
        case .transferFailed: return "Chuyển thất bại"
        }
    }

    /// Optional extra detail for `.transferFailed`.
    var failureDetail: String? {
        if case .transferFailed(let detail) = self, !detail.isEmpty { return detail }
        return nil
    }
}

enum DropTrayStatusEvaluator {
    /// Maps filesystem probe facts + any prior transfer error into a single truthful status.
    /// Permission denial takes precedence when POSIX `stat`/`access` explicitly fails with EACCES/EPERM.
    static func evaluate(
        exists: Bool,
        isReadable: Bool,
        accessDenied: Bool,
        transferError: String? = nil
    ) -> DropTrayItemStatus {
        if accessDenied { return .permissionDenied }
        if !exists { return .movedOrMissing }
        if !isReadable { return .permissionDenied }
        if let err = transferError?.trimmingCharacters(in: .whitespacesAndNewlines), !err.isEmpty {
            return .transferFailed(err)
        }
        return .ready
    }
}

/// Pure multi-selection state for the Drop Tray (supports click, ⌘-toggle, ⇧-range, ⌘A, arrow navigation).
struct DropTraySelection: Equatable, Sendable {
    private(set) var selectedIDs: Set<UUID> = []
    private(set) var anchorID: UUID?
    private(set) var cursorID: UUID?

    var count: Int { selectedIDs.count }
    var isEmpty: Bool { selectedIDs.isEmpty }
    /// Multi-select action bar ("Chia sẻ", "Chép vào ngăn", "Chuyển vào ngăn") surfaces for 2+ selected items.
    var isMultiSelection: Bool { selectedIDs.count >= 2 }

    func contains(_ id: UUID) -> Bool { selectedIDs.contains(id) }

    mutating func click(_ id: UUID, in orderedIDs: [UUID], command: Bool, shift: Bool) {
        if shift, let anchor = anchorID ?? cursorID,
           let start = orderedIDs.firstIndex(of: anchor),
           let end = orderedIDs.firstIndex(of: id) {
            let low = min(start, end)
            let high = max(start, end)
            let range = Set(orderedIDs[low...high])
            if command {
                selectedIDs.formUnion(range)
            } else {
                selectedIDs = range
            }
            cursorID = id
            return
        }

        if command {
            if selectedIDs.contains(id) {
                selectedIDs.remove(id)
            } else {
                selectedIDs.insert(id)
            }
            anchorID = id
            cursorID = id
            return
        }

        selectedIDs = [id]
        anchorID = id
        cursorID = id
    }

    mutating func move(delta: Int, in orderedIDs: [UUID], extend: Bool) {
        guard !orderedIDs.isEmpty else { clear(); return }
        let nextIndex: Int
        if let current = cursorID, let idx = orderedIDs.firstIndex(of: current) {
            nextIndex = max(0, min(orderedIDs.count - 1, idx + delta))
        } else {
            nextIndex = delta >= 0 ? 0 : orderedIDs.count - 1
        }
        let target = orderedIDs[nextIndex]
        if extend {
            let anchor = anchorID ?? cursorID ?? target
            anchorID = anchor
            if let start = orderedIDs.firstIndex(of: anchor) {
                let low = min(start, nextIndex)
                let high = max(start, nextIndex)
                selectedIDs = Set(orderedIDs[low...high])
            } else {
                selectedIDs.insert(target)
            }
        } else {
            selectedIDs = [target]
            anchorID = target
        }
        cursorID = target
    }

    mutating func selectAll(_ orderedIDs: [UUID]) {
        selectedIDs = Set(orderedIDs)
        anchorID = orderedIDs.first
        cursorID = orderedIDs.last
    }

    mutating func clear() {
        selectedIDs.removeAll()
        anchorID = nil
        cursorID = nil
    }

    mutating func prune(validIDs: Set<UUID>) {
        selectedIDs.formIntersection(validIDs)
        if let a = anchorID, !validIDs.contains(a) { anchorID = nil }
        if let c = cursorID, !validIDs.contains(c) { cursorID = nil }
    }
}

/// Pure post-transfer tray reconciliation (XF-T41 failure contract: failed/skipped/cancelled moves
/// MUST keep their items in the tray and surface why; copies always keep items in the tray).
enum DropTrayTransferReconciler {
    struct Outcome: Equatable, Sendable {
        let pathsToRemove: Set<String>
        let failureReasonsByPath: [String: String]
        let clearedErrorPaths: Set<String>
    }

    static func reconcile(
        requestedPaths: [String],
        copy: Bool,
        succeededPaths: Set<String>,
        skippedPaths: Set<String>,
        failedReasons: [String: String],
        cancelled: Bool
    ) -> Outcome {
        let requested = Set(requestedPaths)
        let succeeded = requested.intersection(succeededPaths)

        if copy {
            let reasons = failedReasons.filter { requested.contains($0.key) }
            return Outcome(pathsToRemove: [], failureReasonsByPath: reasons, clearedErrorPaths: succeeded)
        }

        // Move: ONLY items whose transfer actually completed leave the tray.
        var reasons: [String: String] = [:]
        for path in requested where !succeeded.contains(path) {
            if let r = failedReasons[path], !r.isEmpty {
                reasons[path] = r
            } else if skippedPaths.contains(path) {
                reasons[path] = "Đã bỏ qua khi trùng tên"
            } else if cancelled {
                reasons[path] = "Đã dừng trước khi chuyển"
            } else {
                reasons[path] = "Không thể chuyển tệp"
            }
        }
        return Outcome(pathsToRemove: succeeded, failureReasonsByPath: reasons, clearedErrorPaths: [])
    }
}

/// Pure selection-guarded target resolution for Ref-29 Drop Tray actions (AirDrop, Share, Quick Look,
/// Browser Pane Copy/Move, and batch `NotchActions`). When the selection is non-empty, actions operate
/// strictly on selected actionable items and NEVER silently fall back to unselected items if all selected
/// items are missing or unreadable.
enum DropTrayActionResolution {
    struct Entry: Equatable, Sendable {
        let id: UUID
        let isActionable: Bool
    }

    struct Result<Item: Equatable>: Equatable {
        let targets: [Item]
        let hasSelection: Bool
        var hasSelectionWithZeroActionable: Bool { hasSelection && targets.isEmpty }
    }

    static func resolve<Item: Equatable>(
        items: [Item],
        selection: DropTraySelection,
        id: (Item) -> UUID,
        isActionable: (Item) -> Bool
    ) -> Result<Item> {
        if selection.isEmpty {
            return Result(targets: items.filter(isActionable), hasSelection: false)
        }
        let selectedActionable = items.filter { selection.contains(id($0)) && isActionable($0) }
        return Result(targets: selectedActionable, hasSelection: true)
    }

    static func resolve(items: [Entry], selection: DropTraySelection) -> Result<Entry> {
        resolve(items: items, selection: selection, id: \.id, isActionable: \.isActionable)
    }
}
