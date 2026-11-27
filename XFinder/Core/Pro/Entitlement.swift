import Foundation

/// XF-T29 — what each tier may use (symlinked into the test package). One table, one place: every gate in the app asks
/// `allows`/`limit` here (through `LicenseManager`), never an ad-hoc `if isPro`.
///
/// Owner's decisions 2026-10-24: Free keeps 50 clipboard items and 20 captures and gets the everyday features; Pro is
/// scale, automation, security and agents; a 14-day Pro trial starts on first launch; data above a Free limit is HIDDEN,
/// never deleted (spec XF-T29 §1–§2). Builds on the owner's Mac are full: enforcement is off without a release build.
enum ProTier: Equatable, Sendable {
    case free
    case trial(daysLeft: Int)
    case pro

    var isUnlocked: Bool {
        if case .free = self { return false }
        return true
    }
}

enum ProFeature: String, CaseIterable, Sendable {
    case unlimitedClipboard, unlimitedCaptures, lockedBoard, clipboardMCP, scrollingCapture
    case browserPanes, browserWorkspaces, browserQueue, browserBatchCloud
    case agentCrews, windowlessAgents, agentHandoff, folderLock, folderSync, remoteConnect, snapMemory
    case unlimitedQuickShare, voiceAIRefine

    /// L10n key (the Vietnamese source sentence) the Pro page and the gates show.
    var titleKey: String {
        switch self {
        case .unlimitedClipboard: return "Lịch sử Clipboard không giới hạn"
        case .unlimitedCaptures: return "Lịch sử ảnh chụp không giới hạn"
        case .lockedBoard: return "Bảng khoá Clipboard"
        case .clipboardMCP: return "Máy chủ MCP Clipboard cho AI agent"
        case .scrollingCapture: return "Chụp cuộn"
        case .browserPanes: return "Trình duyệt tệp tới 16 ngăn"
        case .browserWorkspaces: return "Workspace có tên"
        case .browserQueue: return "Hàng đợi nhiều thao tác chép"
        case .browserBatchCloud: return "Tải về và gỡ đám mây hàng loạt"
        case .agentCrews: return "Nhóm agent (crew)"
        case .windowlessAgents: return "Phiên agent không cửa sổ"
        case .agentHandoff: return "Chuyển phiên agent"
        case .folderLock: return "Khoá thư mục"
        case .folderSync: return "Đồng bộ thư mục tự động"
        case .remoteConnect: return "Kết nối từ xa"
        case .snapMemory: return "Nhớ bố cục cửa sổ"
        case .unlimitedQuickShare: return "Chia sẻ nhanh không giới hạn liên kết"
        case .voiceAIRefine: return "Tinh chỉnh giọng nói bằng AI"
        }
    }
}

enum ProLimit: String, CaseIterable, Sendable {
    case clipboardItems, captures, browserPanes, quickShareLinks
}

enum Entitlement {
    static let trialDays = 14

    /// The Free tier's numbers (spec XF-T29 §2). Pro and the trial have no limit.
    static let freeLimits: [ProLimit: Int] = [.clipboardItems: 50, .captures: 20, .browserPanes: 2, .quickShareLinks: 1]

    /// The tier right now. Not enforced (a development build) ⇒ Pro. A valid licence ⇒ Pro. No trial yet ⇒ a fresh
    /// 14-day trial (the caller records `trialStart = now`). The clock never runs backwards for the trial: the latest
    /// time ever seen (`maxSeen`) counts, so setting the date back does not buy days.
    static func tier(enforced: Bool, licenseValid: Bool, trialStart: Date?, now: Date, maxSeen: Date?) -> ProTier {
        guard enforced else { return .pro }
        if licenseValid { return .pro }
        guard let start = trialStart else { return .trial(daysLeft: trialDays) }
        let effectiveNow = max(now, maxSeen ?? now)
        let elapsed = max(0, effectiveNow.timeIntervalSince(start))
        // Days still to run, rounded UP: the first day shows 14, the last hours show 1, the full 14 days end it.
        let remaining = Double(trialDays) * 86_400 - elapsed
        guard remaining > 0 else { return .free }
        return .trial(daysLeft: Int((remaining / 86_400).rounded(.up)))
    }

    /// Every `ProFeature` is a Pro feature: unlocked by Pro and the trial, locked in Free.
    static func allows(_ feature: ProFeature, tier: ProTier) -> Bool { tier.isUnlocked }

    /// nil = unlimited.
    static func limit(_ limit: ProLimit, tier: ProTier) -> Int? {
        tier.isUnlocked ? nil : freeLimits[limit]
    }

    /// What a list shows under a limit: pinned items always show and do not count; of the rest, the newest `limit` show
    /// and the remainder is hidden — never deleted (owner's default for Q-PRO-2).
    static func visibleCount(total: Int, pinned: Int, limit: Int?) -> (visible: Int, hidden: Int) {
        let total = max(0, total)
        let pinned = min(max(0, pinned), total)
        guard let limit else { return (total, 0) }
        let others = total - pinned
        let shown = min(others, max(0, limit))
        return (pinned + shown, others - shown)
    }
}
