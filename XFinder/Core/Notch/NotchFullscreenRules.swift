import Foundation

/// User-facing policy for whether the notch should appear over another app's fullscreen window.
enum NotchFullscreenVisibility: String, CaseIterable, Equatable {
    case show
    case hideInFullscreen
    case hideForFullscreenMedia


    static func parse(_ raw: String?) -> NotchFullscreenVisibility {
        raw.flatMap(NotchFullscreenVisibility.init(rawValue:)) ?? .show
    }

    var labelKey: String {
        switch self {
        case .show: return "Luôn hiện notch"
        case .hideInFullscreen: return "Ẩn trong ứng dụng toàn màn hình"
        case .hideForFullscreenMedia: return "Chỉ ẩn khi xem media toàn màn hình"
        }
    }
}

/// Pure matching and policy rules. Detection is deliberately conservative: failure to inspect means show.
enum NotchFullscreenRules {
    struct Context: Equatable {
        var fullscreenOwnerPID: Int32?
        var frontmostPID: Int32?
        var mediaPID: Int32?
        var mediaPlaying = false
        var mustRemainVisible = false
    }

    /// Window-server and display bounds can differ by a few points due to scale/rounding. This is a
    /// geometry tolerance, not a claim that macOS exposes an authoritative fullscreen flag here.
    static let displayFrameTolerance: CGFloat = 8

    static func matchesDisplayFrame(_ window: CGRect, _ display: CGRect,
                                    tolerance: CGFloat = displayFrameTolerance) -> Bool {
        guard window.width > 0, window.height > 0, display.width > 0, display.height > 0,
              tolerance >= 0, tolerance.isFinite else { return false }
        return abs(window.minX - display.minX) <= tolerance
            && abs(window.minY - display.minY) <= tolerance
            && abs(window.width - display.width) <= tolerance
            && abs(window.height - display.height) <= tolerance
    }

    static func shouldHide(_ policy: NotchFullscreenVisibility, context: Context) -> Bool {
        guard !context.mustRemainVisible,
              let owner = context.fullscreenOwnerPID,
              owner == context.frontmostPID else { return false }
        switch policy {
        case .show:
            return false
        case .hideInFullscreen:
            return true
        case .hideForFullscreenMedia:
            return context.mediaPlaying && context.mediaPID == owner
        }
    }
}
