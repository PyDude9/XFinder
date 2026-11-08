import Foundation

/// XF-VOICE-PERMISSIONS (2026-11-08): what one press of the dictation trigger does about the two permissions dictation
/// needs, and how the Voice page labels them. Pure — `VoiceManager` maps the TCC statuses in and acts on the decision.
/// Foundation only: symlinked into the test package (`VoicePermissionRulesTests`).
///
/// Three rules, each a defect of the code this replaced (`docs/specs/XF-VOICE-PERMISSIONS.md`):
/// 1. **A refused permission is never asked again.** macOS answers a repeat request with "denied" and no dialog, so the
///    old code re-asked on every press and the user saw only a generic error.
/// 2. **A refusal wins over an undecided permission.** While one of the two is refused dictation cannot work, so prompting
///    for the other one adds a dialog that changes nothing.
/// 3. **Undecided permissions are asked one at a time, microphone first**, in the press that found them; the caller stops
///    at the first refusal, so a refused microphone never leads to a Speech Recognition prompt.
enum VoicePermissionKind: String, CaseIterable, Sendable {
    case microphone
    case speechRecognition
}

enum VoicePermissionStatus: CaseIterable, Equatable, Sendable {
    case authorized, notDetermined, denied, restricted

    /// macOS will not show a prompt for this permission again.
    var isRefused: Bool { self == .denied || self == .restricted }
}

enum VoiceActivationDecision: Equatable, Sendable {
    /// Both granted: open the microphone.
    case start
    /// Ask macOS for these, in this order, stopping at the first refusal. Never empty.
    case ask([VoicePermissionKind])
    /// Refused (or restricted by Screen Time / device management): say which one; call no request API.
    case blocked(VoicePermissionKind, restricted: Bool)
}

enum VoicePermissionRules {

    static func decide(microphone: VoicePermissionStatus, speech: VoicePermissionStatus) -> VoiceActivationDecision {
        let statuses: [(kind: VoicePermissionKind, status: VoicePermissionStatus)] = [
            (.microphone, microphone),
            (.speechRecognition, speech),
        ]
        if let refused = statuses.first(where: { $0.status.isRefused }) {
            return .blocked(refused.kind, restricted: refused.status == .restricted)
        }
        let undecided = statuses.filter { $0.status == .notDetermined }.map(\.kind)
        return undecided.isEmpty ? .start : .ask(undecided)
    }

    // MARK: HUD lines (one line, 13 pt, 350 pt wide — measured 2026-11-08: the longest, VI speech-denied, is 301.5 pt)

    /// The headline when a press does not start. The HUD's second line already says where to look
    /// ("Thử lại hoặc kiểm tra quyền trong trang Nhập bằng giọng nói."), so this names only WHICH permission.
    static func blockedMessageKey(_ kind: VoicePermissionKind, restricted: Bool) -> String {
        switch (kind, restricted) {
        case (.microphone, false): return "Micro đang bị từ chối cho XFinder"
        case (.speechRecognition, false): return "Nhận dạng giọng nói đang bị từ chối cho XFinder"
        case (.microphone, true): return "Micro bị giới hạn trên máy này"
        case (.speechRecognition, true): return "Nhận dạng giọng nói bị giới hạn trên máy này"
        }
    }

    /// After every asked permission was granted. The trigger was released while the dialog was up, so the press that
    /// asked does not start a session: the user presses again.
    static let grantedNoticeKey = "Đã cấp quyền — nhấn phím lần nữa để nói"

    // MARK: Voice page rows

    static func rowStatusKey(_ status: VoicePermissionStatus) -> String {
        switch status {
        case .authorized: return "Đã cấp"
        case .notDetermined: return "Cần cấp quyền"
        case .denied: return "Đã từ chối"
        case .restricted: return "Bị giới hạn"
        }
    }

    /// The row's button. Undecided ⇒ ask; refused ⇒ the Privacy pane is the only place that can change it (the request
    /// API returns at once without a dialog); restricted ⇒ nothing the user can do from XFinder.
    static func rowActionKey(_ status: VoicePermissionStatus) -> String? {
        switch status {
        case .authorized, .restricted: return nil
        case .notDetermined: return "Yêu cầu"
        case .denied: return "Mở Cài đặt hệ thống"
        }
    }

    /// Every key this file can hand to `L10n.t` — the vocabulary test checks each is in the shipped store.
    static var allKeys: [String] {
        var keys = [grantedNoticeKey]
        for kind in VoicePermissionKind.allCases {
            keys.append(blockedMessageKey(kind, restricted: false))
            keys.append(blockedMessageKey(kind, restricted: true))
        }
        for status in VoicePermissionStatus.allCases {
            keys.append(rowStatusKey(status))
            if let action = rowActionKey(status) { keys.append(action) }
        }
        return keys
    }
}
